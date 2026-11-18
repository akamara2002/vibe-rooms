-- =============================================================================
-- verify_behavior.sql : simulates three users and checks RLS and RPC behaviour.
--
-- Run in the Supabase SQL editor (as postgres) AFTER 0001_init.sql.
-- EXPECTED RESULT: an error whose message starts with  VERIFY_OK
-- Any message starting with VERIFY_FAIL names the check that failed.
-- Nothing is ever saved: the block always ends by raising an exception, which
-- rolls back the fake users and everything they created.
--
-- Users are simulated like Supabase does it: JWT claims in the
-- request.jwt.claims setting plus "set local role authenticated". Between
-- steps we "reset role" to go back to the owner.
-- =============================================================================

do $$
declare
  v_host      uuid := gen_random_uuid();
  v_guest     uuid := gen_random_uuid();
  v_out       uuid := gen_random_uuid();
  v_room      public.rooms;
  v_joined    public.rooms;
  v_n         int;
  v_text      text;
  v_ts        timestamptz;
  v_ts2       timestamptz;
  v_by        uuid;
  v_item      uuid;   -- guest's queue item
  v_host_item uuid;   -- host's queue item
  v_failed    boolean;
begin
  -- ---------------------------------------------------------------------------
  -- Setup (as owner): three fake users. The trigger must create their profiles.
  -- ---------------------------------------------------------------------------
  insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values
    (v_host,  'authenticated', 'authenticated', 'verify-host-'  || v_host  || '@example.invalid',
     '{"display_name": "  Verify Host  "}'::jsonb, now(), now()),
    (v_guest, 'authenticated', 'authenticated', 'verify-guest-' || v_guest || '@example.invalid',
     '{}'::jsonb, now(), now()),
    (v_out,   'authenticated', 'authenticated', 'verify-out-'   || v_out   || '@example.invalid',
     '{}'::jsonb, now(), now());

  select count(*) into v_n from public.profiles where id in (v_host, v_guest, v_out);
  if v_n <> 3 then
    raise exception 'VERIFY_FAIL: handle_new_user did not create 3 profiles (got %)', v_n;
  end if;

  select display_name into v_text from public.profiles where id = v_host;
  if v_text <> 'Verify Host' then
    raise exception 'VERIFY_FAIL: display_name was not trimmed from metadata (got "%")', v_text;
  end if;

  select display_name into v_text from public.profiles where id = v_guest;
  if v_text <> 'Guest ' || upper(left(replace(v_guest::text, '-', ''), 4)) then
    raise exception 'VERIFY_FAIL: default guest display_name wrong (got "%")', v_text;
  end if;

  -- ---------------------------------------------------------------------------
  -- (a) host creates a room; code matches the alphabet regex
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select * into v_room from public.create_room('  Verify Room  ');

  if v_room.code is null or v_room.code !~ '^[A-HJ-NP-Z2-9]{6}$' then
    raise exception 'VERIFY_FAIL: (a) room code "%" does not match the regex', v_room.code;
  end if;
  if v_room.name <> 'Verify Room' or v_room.host_id <> v_host then
    raise exception 'VERIFY_FAIL: (a) room name/host wrong (name "%", host %)', v_room.name, v_room.host_id;
  end if;

  select count(*) into v_n from public.room_state where room_id = v_room.id;
  if v_n <> 1 then
    raise exception 'VERIFY_FAIL: (a) host cannot see exactly one room_state row (got %)', v_n;
  end if;

  select count(*) into v_n from public.room_members where room_id = v_room.id and user_id = v_host;
  if v_n <> 1 then
    raise exception 'VERIFY_FAIL: (a) host is not a member of their own room';
  end if;

  v_failed := false;
  begin
    perform public.create_room('   ');
  exception when others then
    v_failed := sqlerrm = 'invalid_name';
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (a) blank room name was not rejected with invalid_name';
  end if;

  reset role;

  -- ---------------------------------------------------------------------------
  -- (b) guest joins with the code lower-cased and padded with spaces
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select * into v_joined from public.join_room('  ' || lower(v_room.code) || '  ');
  if v_joined.id is distinct from v_room.id then
    raise exception 'VERIFY_FAIL: (b) guest joined the wrong room';
  end if;

  select count(*) into v_n from public.rooms;
  if v_n <> 1 then
    raise exception 'VERIFY_FAIL: (b) guest should see exactly 1 room (got %)', v_n;
  end if;

  select count(*) into v_n from public.room_members where room_id = v_room.id;
  if v_n <> 2 then
    raise exception 'VERIFY_FAIL: (b) guest should see 2 members (got %)', v_n;
  end if;

  -- joining twice is harmless
  perform public.join_room(v_room.code);

  reset role;

  -- ---------------------------------------------------------------------------
  -- (c) outsider sees 0 rooms and cannot join with a wrong code
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_out, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_n from public.rooms;
  if v_n <> 0 then
    raise exception 'VERIFY_FAIL: (c) outsider sees % rooms, expected 0', v_n;
  end if;

  v_failed := false;
  begin
    perform public.join_room('ZZZZZZ');
  exception when sqlstate 'P0002' then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (c) join_room with a wrong code did not raise room_not_found';
  end if;

  -- ---------------------------------------------------------------------------
  -- (d) outsider cannot insert a message, guest can
  -- ---------------------------------------------------------------------------
  v_failed := false;
  begin
    insert into public.messages (room_id, user_id, body) values (v_room.id, v_out, 'let me in');
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (d) outsider inserted a message';
  end if;

  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into public.messages (room_id, user_id, body) values (v_room.id, v_guest, 'hello room');

  v_failed := false;
  begin  -- guest must not post as someone else
    insert into public.messages (room_id, user_id, body) values (v_room.id, v_host, 'spoofed');
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (d) guest posted a message as another user';
  end if;

  v_failed := false;
  begin  -- messages cannot be edited
    update public.messages set body = 'edited' where room_id = v_room.id;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (d) guest could update a message';
  end if;

  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_out, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.messages;
  if v_n <> 0 then
    raise exception 'VERIFY_FAIL: (d) outsider can read % messages', v_n;
  end if;
  reset role;

  -- ---------------------------------------------------------------------------
  -- (e) guest cannot update room_state (0 rows); host can; clock cannot be faked
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  set local role authenticated;

  update public.room_state set is_playing = true where room_id = v_room.id;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'VERIFY_FAIL: (e) guest updated % room_state rows, expected 0', v_n;
  end if;

  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- Forging updated_at is refused outright (no column privilege) ...
  v_failed := false;
  begin
    update public.room_state
       set is_playing = true, position_ms = 1000, updated_at = '2000-01-01'
     where room_id = v_room.id;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (e) host was allowed to write updated_at';
  end if;

  -- ... and a normal host update works and is stamped by the server.
  update public.room_state
     set is_playing = true, position_ms = 1000
   where room_id = v_room.id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'VERIFY_FAIL: (e) host updated % room_state rows, expected 1', v_n;
  end if;

  select updated_at, updated_by into v_ts, v_by from public.room_state where room_id = v_room.id;
  if abs(extract(epoch from (clock_timestamp() - v_ts))) > 5 then
    raise exception 'VERIFY_FAIL: (e) updated_at not server time (%)', v_ts;
  end if;
  if v_by is distinct from v_host then
    raise exception 'VERIFY_FAIL: (e) updated_by is not the host (%)', v_by;
  end if;

  reset role;

  -- The trigger itself must also neutralise a forged clock, even for a writer
  -- that bypasses column grants (here: the owner, with the host's claims set).
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  update public.room_state
     set updated_at = '2000-01-01', updated_by = v_out, room_id = gen_random_uuid()
   where room_id = v_room.id;
  select updated_at, updated_by into v_ts, v_by from public.room_state where room_id = v_room.id;
  if v_ts is null then
    raise exception 'VERIFY_FAIL: (e) trigger let room_id change';
  end if;
  if abs(extract(epoch from (clock_timestamp() - v_ts))) > 5 then
    raise exception 'VERIFY_FAIL: (e) trigger did not overwrite a forged updated_at (%)', v_ts;
  end if;
  if v_by is distinct from v_host then
    raise exception 'VERIFY_FAIL: (e) trigger did not overwrite a forged updated_by (%)', v_by;
  end if;

  -- ---------------------------------------------------------------------------
  -- (f) guest adds a queue item as themselves, not as someone else
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into public.queue_items (room_id, added_by, track_id, title, artist, duration_ms)
  values (v_room.id, v_guest, 'aud-1', 'Guest Song', 'Guest Artist', 180000)
  returning id into v_item;

  v_failed := false;
  begin
    insert into public.queue_items (room_id, added_by, track_id, title, duration_ms)
    values (v_room.id, v_host, 'aud-2', 'Spoofed Song', 1000);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (f) guest added a queue item as another user';
  end if;

  v_failed := false;
  begin  -- sort_key is generated: clients can never write it
    insert into public.queue_items (room_id, added_by, track_id, title, duration_ms, sort_key)
    overriding system value
    values (v_room.id, v_guest, 'aud-3', 'Sneaky Song', 1000, 0);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (f) guest could write sort_key';
  end if;

  -- (k) abuse limits: artwork must be https; avatar_emoji and titles are capped
  v_failed := false;
  begin
    insert into public.queue_items (room_id, added_by, track_id, title, duration_ms, artwork_url)
    values (v_room.id, v_guest, 'aud-6', 'Tracker', 1000, 'http://tracker.example/pixel.png');
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (k) non-https artwork_url was accepted';
  end if;

  v_failed := false;
  begin
    insert into public.queue_items (room_id, added_by, track_id, title, duration_ms)
    values (v_room.id, v_guest, 'aud-7', repeat('x', 301), 1000);
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (k) a 301-character title was accepted';
  end if;

  v_failed := false;
  begin
    update public.profiles set avatar_emoji = repeat('x', 17) where id = v_guest;
  exception when check_violation then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (k) a 17-character avatar_emoji was accepted';
  end if;

  update public.profiles set avatar_emoji = '👨‍👩‍👧‍👦' where id = v_guest;  -- a long ZWJ emoji must still fit
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'VERIFY_FAIL: (k) guest could not update their own avatar_emoji';
  end if;

  v_failed := false;
  begin  -- nobody can edit someone else's profile
    update public.profiles set display_name = 'hacked' where id = v_host;
    get diagnostics v_n = row_count;
    v_failed := (v_n = 0);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (k) guest edited the host''s profile';
  end if;

  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_out, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_failed := false;
  begin
    insert into public.queue_items (room_id, added_by, track_id, title, duration_ms)
    values (v_room.id, v_out, 'aud-4', 'Outsider Song', 1000);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (f) outsider added a queue item';
  end if;
  reset role;

  -- ---------------------------------------------------------------------------
  -- (g) guest cannot delete the host's queue item; host can delete the guest's
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into public.queue_items (room_id, added_by, track_id, title, artist, duration_ms)
  values (v_room.id, v_host, 'aud-5', 'Host Song', 'Host Artist', 200000)
  returning id into v_host_item;

  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_guest, 'role', 'authenticated')::text, true);
  set local role authenticated;

  delete from public.queue_items where id = v_host_item;
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'VERIFY_FAIL: (g) guest deleted the host''s queue item';
  end if;

  v_failed := false;
  begin  -- guests cannot move or edit items (only the host marks played_at)
    update public.queue_items set played_at = now() where id = v_item;
    get diagnostics v_n = row_count;
    v_failed := (v_n = 0);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (g) guest updated a queue item';
  end if;

  reset role;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  set local role authenticated;

  delete from public.queue_items where id = v_item;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'VERIFY_FAIL: (g) host could not delete the guest''s queue item';
  end if;

  reset role;

  -- ---------------------------------------------------------------------------
  -- (h) outsider cannot read room_state
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_out, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_n from public.room_state where room_id = v_room.id;
  if v_n <> 0 then
    raise exception 'VERIFY_FAIL: (h) outsider can read room_state';
  end if;

  select count(*) into v_n from public.queue_items where room_id = v_room.id;
  if v_n <> 0 then
    raise exception 'VERIFY_FAIL: (h) outsider can read queue_items';
  end if;

  reset role;

  -- ---------------------------------------------------------------------------
  -- (i) deleting the playing queue item must NOT move the playback anchor
  --     (the "on delete set null" update must not bump updated_at)
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_host, 'role', 'authenticated')::text, true);
  set local role authenticated;

  update public.room_state
     set queue_item_id = v_host_item, track_id = 'aud-5', title = 'Host Song',
         duration_ms = 200000, is_playing = true, position_ms = 5000
   where room_id = v_room.id;

  select updated_at into v_ts from public.room_state where room_id = v_room.id;
  perform pg_sleep(0.1);

  delete from public.queue_items where id = v_host_item;

  select updated_at into v_ts2 from public.room_state where room_id = v_room.id;
  select count(*) into v_n from public.room_state
   where room_id = v_room.id and queue_item_id is null and position_ms = 5000 and is_playing;
  if v_n <> 1 then
    raise exception 'VERIFY_FAIL: (i) deleting the playing item did not null queue_item_id cleanly';
  end if;
  if v_ts2 is distinct from v_ts then
    raise exception 'VERIFY_FAIL: (i) deleting the playing item moved updated_at (% -> %)', v_ts, v_ts2;
  end if;

  reset role;

  -- ---------------------------------------------------------------------------
  -- (j) anon (not signed in) can use nothing
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);
  set local role anon;

  v_failed := false;
  begin
    perform count(*) from public.rooms;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (j) anon can read rooms';
  end if;

  v_failed := false;
  begin
    perform public.join_room(v_room.code);
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'VERIFY_FAIL: (j) anon can call join_room';
  end if;

  reset role;

  -- ---------------------------------------------------------------------------
  -- Done. Roll everything back on purpose.
  -- ---------------------------------------------------------------------------
  raise exception 'VERIFY_OK: all checks passed (rolled back by design)';
end;
$$;
