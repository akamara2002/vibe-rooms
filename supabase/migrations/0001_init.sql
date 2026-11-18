-- =============================================================================
-- 0001_init.sql : Vibe Rooms schema, RLS, RPCs and realtime setup.
--
-- Written to run ONCE on an EMPTY Supabase project (SQL editor, as postgres).
-- To start over during development, run 0000_reset_dev.sql first (deletes all
-- app data), then run this file again.
--
-- Contents, in dependency order:
--   1. Tables and indexes
--   2. Trigger functions and triggers
--   3. Helper functions and RPCs (is_room_member, is_room_host, create_room,
--      join_room, server_now)
--   4. Privileges (anon gets nothing; authenticated gets what policies need)
--   5. Row level security policies
--   6. Realtime publication and replica identity
--
-- Security notes:
--   * Every SECURITY DEFINER function pins search_path to "public, pg_temp" and
--     schema-qualifies its objects, so a caller cannot hijack names with temp
--     tables.
--   * Clients write only through column-level grants, so they cannot change
--     rooms.host_id, rooms.code, queue_items.room_id, etc.
--   * room_state.updated_at/updated_by are set by a trigger; clients can never
--     fake the time.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null check (char_length(display_name) between 1 and 30),
  -- emoji sequences (ZWJ families, flags) fit in 16 code points; the cap stops
  -- a user storing a huge string that every room member would download
  avatar_emoji  text not null default '🎧' check (char_length(avatar_emoji) between 1 and 16),
  created_at    timestamptz not null default now()
);

create table public.rooms (
  id          uuid primary key default gen_random_uuid(),
  -- 6 chars from an alphabet without 0, O, 1, I
  code        text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  name        text not null check (char_length(name) between 1 and 40),
  host_id     uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  closed_at   timestamptz null
);

create table public.room_members (
  room_id    uuid not null references public.rooms (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  joined_at  timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table public.queue_items (
  id           uuid primary key default gen_random_uuid(),
  room_id      uuid not null references public.rooms (id) on delete cascade,
  added_by     uuid not null references public.profiles (id) on delete cascade,
  track_id     text not null check (char_length(track_id) <= 100),  -- Audius track id
  title        text not null check (char_length(title) <= 300),
  artist       text not null default '' check (char_length(artist) <= 300),
  -- https only: every member's client fetches this URL
  artwork_url  text null check (artwork_url ~ '^https://[^[:space:]]+$' and char_length(artwork_url) <= 2048),
  duration_ms  integer not null check (duration_ms > 0),
  sort_key     bigint generated always as identity,  -- clients can never write it
  played_at    timestamptz null,
  created_at   timestamptz not null default now()
);

-- One row per room. queue_items exists already, so the FK can be inline.
create table public.room_state (
  room_id        uuid primary key references public.rooms (id) on delete cascade,
  queue_item_id  uuid null references public.queue_items (id) on delete set null,
  track_id       text null check (char_length(track_id) <= 100),
  title          text null check (char_length(title) <= 300),
  artist         text null check (char_length(artist) <= 300),
  artwork_url    text null check (artwork_url ~ '^https://[^[:space:]]+$' and char_length(artwork_url) <= 2048),
  duration_ms    integer null check (duration_ms > 0),
  is_playing     boolean not null default false,
  position_ms    integer not null default 0 check (position_ms >= 0),
  updated_at     timestamptz not null default clock_timestamp(),
  updated_by     uuid null
);

create table public.messages (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.rooms (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  body        text not null check (char_length(btrim(body)) between 1 and 500),
  created_at  timestamptz not null default now()
);

create index room_members_user_id_idx    on public.room_members (user_id);
create index queue_items_room_sort_idx   on public.queue_items (room_id, sort_key);
create index messages_room_created_idx   on public.messages (room_id, created_at);

-- -----------------------------------------------------------------------------
-- 2. Trigger functions and triggers
-- -----------------------------------------------------------------------------

-- Creates a profile for every new auth user (anonymous ones included).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
begin
  v_name := btrim(left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), 30));
  if v_name = '' then
    v_name := 'Guest ' || upper(left(replace(new.id::text, '-', ''), 4));
  end if;

  insert into public.profiles (id, display_name)
  values (new.id, v_name)
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Clients can never fake the playback clock or move a state row to another room.
create function public.room_state_touch()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.room_id := old.room_id;

  -- Depth > 1 means this UPDATE was fired by a foreign-key action, e.g.
  -- "on delete set null" when the playing queue item is deleted. That must NOT
  -- move the playback anchor (position_ms + updated_at), or every client would
  -- jump back in time. Only a direct write bumps the clock.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  new.updated_at := clock_timestamp();
  new.updated_by := auth.uid();
  return new;
end;
$$;

create trigger room_state_touch
  before update on public.room_state
  for each row execute function public.room_state_touch();

-- -----------------------------------------------------------------------------
-- 3. Helper functions and RPCs
-- -----------------------------------------------------------------------------

create function public.is_room_member(p_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.room_members m
    where m.room_id = p_room
      and m.user_id = auth.uid()
  );
$$;

create function public.is_room_host(p_room uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = p_room
      and r.host_id = auth.uid()
  );
$$;

create function public.create_room(p_name text)
returns public.rooms
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_name      text := btrim(coalesce(p_name, ''));
  v_alphabet  constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- 32 chars
  v_bytes     bytea;
  v_code      text;
  v_room      public.rooms;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name';
  end if;

  for v_attempt in 1..10 loop
    -- Room codes act as a bearer secret, so draw them from a CSPRNG.
    -- A uuid's first 6 bytes are fully random; 256 % 32 = 0 so there is no bias.
    v_bytes := uuid_send(gen_random_uuid());
    v_code := '';
    for v_i in 0..5 loop
      v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, v_i) % 32) + 1, 1);
    end loop;

    begin
      insert into public.rooms (code, name, host_id)
      values (v_code, v_name, v_uid)
      returning * into v_room;
      exit;
    exception when unique_violation then
      v_room := null;
    end;
  end loop;

  if v_room.id is null then
    raise exception 'code_generation_failed';
  end if;

  insert into public.room_members (room_id, user_id) values (v_room.id, v_uid);
  insert into public.room_state (room_id) values (v_room.id);

  return v_room;
end;
$$;

create function public.join_room(p_code text)
returns public.rooms
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_code  text := upper(btrim(coalesce(p_code, '')));
  v_room  public.rooms;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select * into v_room
  from public.rooms r
  where r.code = v_code
    and r.closed_at is null;

  if not found then
    raise exception 'room_not_found' using errcode = 'P0002';
  end if;

  insert into public.room_members (room_id, user_id)
  values (v_room.id, v_uid)
  on conflict do nothing;

  return v_room;
end;
$$;

-- Clients call this to measure their clock offset from the server.
create function public.server_now()
returns timestamptz
language sql
volatile
security definer
set search_path = public, pg_temp
as $$
  select clock_timestamp();
$$;

-- Execute privileges. Supabase grants EXECUTE to anon/authenticated by default,
-- so anon must be revoked by name (revoking from public is not enough).
revoke execute on function public.handle_new_user()          from public, anon, authenticated;
revoke execute on function public.room_state_touch()         from public, anon, authenticated;
revoke execute on function public.is_room_member(uuid)       from public, anon;
revoke execute on function public.is_room_host(uuid)         from public, anon;
revoke execute on function public.create_room(text)          from public, anon;
revoke execute on function public.join_room(text)            from public, anon;
revoke execute on function public.server_now()               from public, anon;

grant execute on function public.is_room_member(uuid)  to authenticated;
grant execute on function public.is_room_host(uuid)    to authenticated;
grant execute on function public.create_room(text)     to authenticated;
grant execute on function public.join_room(text)       to authenticated;
grant execute on function public.server_now()          to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Table privileges (RLS decides which rows; grants decide which columns)
-- -----------------------------------------------------------------------------

revoke all on table
  public.profiles, public.rooms, public.room_members,
  public.queue_items, public.room_state, public.messages
from public, anon, authenticated;

grant select on
  public.profiles, public.rooms, public.room_members,
  public.queue_items, public.room_state, public.messages
to authenticated;

-- profiles: a user may insert/update only their own row (policy), and only these columns
grant insert (id, display_name, avatar_emoji) on public.profiles to authenticated;
grant update (display_name, avatar_emoji)     on public.profiles to authenticated;

-- rooms: no client insert/delete (create_room does it). Host may rename or close.
grant update (name, closed_at) on public.rooms to authenticated;

-- room_members: no client insert (join_room does it). Members may leave.
grant delete on public.room_members to authenticated;

-- room_state: host writes playback columns only. updated_at/updated_by/room_id
-- are not grantable; the trigger sets them.
grant update (queue_item_id, track_id, title, artist, artwork_url,
              duration_ms, is_playing, position_ms)
  on public.room_state to authenticated;

-- queue_items: sort_key, id and created_at are never client-written.
grant insert (room_id, added_by, track_id, title, artist, artwork_url, duration_ms)
  on public.queue_items to authenticated;
grant update (played_at) on public.queue_items to authenticated;
grant delete             on public.queue_items to authenticated;

-- messages: insert only. No update or delete.
grant insert (room_id, user_id, body) on public.messages to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Row level security (enabled on every table)
-- -----------------------------------------------------------------------------

alter table public.profiles      enable row level security;
alter table public.rooms         enable row level security;
alter table public.room_members  enable row level security;
alter table public.queue_items   enable row level security;
alter table public.room_state    enable row level security;
alter table public.messages      enable row level security;

-- profiles
create policy "profiles_select_authenticated" on public.profiles
  for select to authenticated using (true);
create policy "profiles_insert_self" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles_update_self" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- rooms (no client insert or delete: create_room does it)
create policy "rooms_select_member" on public.rooms
  for select to authenticated using (public.is_room_member(id));
create policy "rooms_update_host" on public.rooms
  for update to authenticated
  using (public.is_room_host(id))
  with check (public.is_room_host(id));

-- room_members (no client insert: join_room does it)
create policy "room_members_select_member" on public.room_members
  for select to authenticated using (public.is_room_member(room_id));
create policy "room_members_delete_self" on public.room_members
  for delete to authenticated using (user_id = (select auth.uid()));

-- room_state (no client insert or delete)
create policy "room_state_select_member" on public.room_state
  for select to authenticated using (public.is_room_member(room_id));
create policy "room_state_update_host" on public.room_state
  for update to authenticated
  using (public.is_room_host(room_id))
  with check (public.is_room_host(room_id));

-- queue_items
create policy "queue_items_select_member" on public.queue_items
  for select to authenticated using (public.is_room_member(room_id));
create policy "queue_items_insert_member" on public.queue_items
  for insert to authenticated
  with check (public.is_room_member(room_id) and added_by = (select auth.uid()));
create policy "queue_items_update_host" on public.queue_items
  for update to authenticated
  using (public.is_room_host(room_id))
  with check (public.is_room_host(room_id));
create policy "queue_items_delete_host_or_owner" on public.queue_items
  for delete to authenticated
  using (public.is_room_host(room_id) or added_by = (select auth.uid()));

-- messages (no update or delete)
create policy "messages_select_member" on public.messages
  for select to authenticated using (public.is_room_member(room_id));
create policy "messages_insert_member" on public.messages
  for insert to authenticated
  with check (public.is_room_member(room_id) and user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- 6. Realtime
-- -----------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach v_table in array array['room_state', 'queue_items', 'messages', 'room_members']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;

-- Note: Realtime does not apply RLS to DELETE events and sends only the primary
-- key in the old record. Clients must remove rows by id on DELETE.
alter table public.room_state    replica identity full;
alter table public.queue_items   replica identity full;
alter table public.room_members  replica identity full;

-- -----------------------------------------------------------------------------
-- 7. Backfill: profiles for auth users that existed before this migration
--    (needed when re-running after 0000_reset_dev.sql, which keeps auth.users).
-- -----------------------------------------------------------------------------

insert into public.profiles (id, display_name)
select u.id,
       coalesce(
         nullif(btrim(left(btrim(coalesce(u.raw_user_meta_data ->> 'display_name', '')), 30)), ''),
         'Guest ' || upper(left(replace(u.id::text, '-', ''), 4))
       )
from auth.users u
on conflict (id) do nothing;
