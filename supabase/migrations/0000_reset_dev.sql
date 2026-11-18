-- =============================================================================
-- !!!  WARNING: DEVELOPMENT ONLY. THIS FILE DELETES ALL VIBE ROOMS DATA.  !!!
--
-- Drops every table, function, trigger and realtime membership that
-- 0001_init.sql creates: profiles, rooms, room_members, queue_items,
-- room_state, messages (and all their rows). Do NOT run it on a project that
-- holds data you want to keep.
--
-- It does not touch auth.users. After running it, run 0001_init.sql again; that
-- file backfills a profile for every existing auth user.
-- =============================================================================

-- Realtime publication membership (guarded: only tables that exist and are members)
do $$
declare
  v_table text;
begin
  foreach v_table in array array['room_state', 'queue_items', 'messages', 'room_members']
  loop
    if exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime drop table public.%I', v_table);
    end if;
  end loop;
end;
$$;

-- Trigger on auth.users (the table itself is Supabase's, so only the trigger goes)
drop trigger if exists on_auth_user_created on auth.users;

-- Tables (policies, indexes and table triggers go with them)
drop table if exists public.messages      cascade;
drop table if exists public.room_state    cascade;
drop table if exists public.queue_items   cascade;
drop table if exists public.room_members  cascade;
drop table if exists public.rooms         cascade;
drop table if exists public.profiles      cascade;

-- Functions
drop function if exists public.create_room(text);
drop function if exists public.join_room(text);
drop function if exists public.server_now();
drop function if exists public.is_room_member(uuid);
drop function if exists public.is_room_host(uuid);
drop function if exists public.handle_new_user();
drop function if exists public.room_state_touch();
