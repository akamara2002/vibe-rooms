-- =============================================================================
-- verify_structure.sql : read-only. Run after 0001_init.sql.
--
-- Returns ONE table (the Supabase SQL editor only shows the last result set).
-- How to read it:
--   section "table"       : every row should say "RLS on" and the policy count
--                           (profiles 3, rooms 2, room_members 2, room_state 2,
--                           queue_items 4, messages 2).
--   section "function"    : app functions should be "security definer" with a
--                           search_path, and anon must NOT be able to execute.
--                           handle_new_user / room_state_touch are trigger
--                           functions: nobody can execute them directly.
--   section "realtime"    : the 4 tables must be "in supabase_realtime".
--                           room_state, queue_items, room_members: replica
--                           identity "full".
--   section "anon grants" : must say "none (good)".
-- Anything marked <-- PROBLEM needs fixing.
-- =============================================================================

select 'table' as section,
       c.relname::text as name,
       case when c.relrowsecurity then 'RLS on' else 'RLS OFF  <-- PROBLEM' end
         || ', ' || (select count(*) from pg_policies p
                     where p.schemaname = 'public' and p.tablename = c.relname)::text
         || ' policies' as detail
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in ('profiles', 'rooms', 'room_members', 'queue_items', 'room_state', 'messages')

union all

select 'function',
       p.proname::text || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       case when p.prosecdef then 'security definer' else 'invoker' end
         || '; ' || coalesce(
              (select string_agg(cfg, ',') from unnest(p.proconfig) as cfg
               where cfg like 'search_path=%'),
              'search_path NOT SET  <-- PROBLEM for security definer')
         || '; anon can execute=' || has_function_privilege('anon', p.oid, 'execute')::text
         || '; authenticated can execute=' || has_function_privilege('authenticated', p.oid, 'execute')::text
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('is_room_member', 'is_room_host', 'create_room', 'join_room',
                    'server_now', 'handle_new_user', 'room_state_touch')

union all

select 'realtime',
       t.name,
       case when exists (
              select 1 from pg_publication_tables pt
              where pt.pubname = 'supabase_realtime'
                and pt.schemaname = 'public'
                and pt.tablename = t.name)
            then 'in supabase_realtime'
            else 'NOT in publication  <-- PROBLEM' end
         || '; replica identity='
         || coalesce((select case c.relreplident
                               when 'f' then 'full'
                               when 'd' then 'default'
                               when 'n' then 'nothing'
                               else 'index' end
                      from pg_class c
                      join pg_namespace n on n.oid = c.relnamespace
                      where n.nspname = 'public' and c.relname = t.name), 'table missing')
from (values ('room_state'), ('queue_items'), ('messages'), ('room_members')) as t(name)

union all

select 'anon grants',
       'public tables',
       coalesce(
         (select string_agg(distinct g.table_name || ':' || g.privilege_type, ', ')
          from information_schema.role_table_grants g
          where g.grantee = 'anon'
            and g.table_schema = 'public'
            and g.table_name in ('profiles', 'rooms', 'room_members', 'queue_items',
                                 'room_state', 'messages')),
         'none (good)')

order by 1, 2;
