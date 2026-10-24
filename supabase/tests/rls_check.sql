-- RLS check. Paste into the Supabase dashboard SQL editor (or run with psql -v ON_ERROR_STOP=1).
-- It creates two throwaway users, tries to cross the line as each role, raises an exception on the
-- first failure, and ROLLS BACK so nothing is kept. Last line prints "RLS checks passed".
begin;

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'rls_a@study.example'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'rls_b@study.example');   -- profiles created by trigger

-- Rows owned by B that A must never see (inserted as the table owner, like the Edge Function would).
insert into public.activities (id, participant_id, name, category, duration_min, location, priority)
  values ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'B walk', 'movement', 10, 'anywhere', 1);
insert into public.gaps (id, participant_id, start_time, minutes)
  values ('bbbbbbbb-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-00000000000b', now(), 20);
insert into public.suggestion_sets (id, participant_id, gap_id)
  values ('bbbbbbbb-0000-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-0000-0000-0000-000000000002');
insert into public.suggestions (id, set_id, sources, title, description, duration_min, position)
  values ('bbbbbbbb-0000-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000003', array['A'], 't', 'd', 5, 0);
insert into public.outcomes (participant_id, set_id, chosen_suggestion_id)
  values ('bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-0000-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000004');

-- A's own gap and set, so A has something legitimate to work with.
insert into public.gaps (id, participant_id, start_time, minutes)
  values ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', now(), 20);
insert into public.suggestion_sets (id, participant_id, gap_id)
  values ('aaaaaaaa-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-0000-0000-0000-000000000002');
insert into public.suggestions (id, set_id, sources, title, description, duration_min, position)
  values ('aaaaaaaa-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000003', array['C'], 't', 'd', 5, 0);

-- ===== act as participant A =====
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-00000000000a', true);

do $$
declare n int;
begin
  -- reads: A sees only A
  select count(*) into n from public.profiles;
  if n <> 1 then raise exception 'FAIL profiles visible to A: %', n; end if;
  select count(*) into n from public.activities;   if n <> 0 then raise exception 'FAIL activities leak: %', n; end if;
  select count(*) into n from public.gaps;         if n <> 1 then raise exception 'FAIL gaps visible: %', n; end if;
  select count(*) into n from public.suggestion_sets; if n <> 1 then raise exception 'FAIL sets visible: %', n; end if;
  select count(id) into n from public.suggestions; if n <> 1 then raise exception 'FAIL suggestions visible: %', n; end if;
  select count(*) into n from public.outcomes;     if n <> 0 then raise exception 'FAIL outcomes leak: %', n; end if;

  -- own writes work
  insert into public.activities (name, category, duration_min, location, priority)
    values ('A stretch', 'yoga', 15, 'anywhere', 2);                       -- participant_id defaults to auth.uid()
  insert into public.gaps (start_time, minutes) values (now(), 30);
  update public.profiles set wellness_statement = 'calm' where id = auth.uid();
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL A cannot update own profile'; end if;
  insert into public.outcomes (set_id, chosen_suggestion_id)
    values ('aaaaaaaa-0000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000004');
  update public.outcomes set completed = true, fit_rating = 4 where set_id = 'aaaaaaaa-0000-0000-0000-000000000003';
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL A cannot update own outcome'; end if;

  -- writes into B's rows are blocked or affect nothing
  update public.profiles set wellness_statement = 'hacked' where id = 'bbbbbbbb-0000-0000-0000-00000000000b';
  get diagnostics n = row_count;  if n <> 0 then raise exception 'FAIL A updated B profile'; end if;
  update public.outcomes set completed = false where set_id = 'bbbbbbbb-0000-0000-0000-000000000003';
  get diagnostics n = row_count;  if n <> 0 then raise exception 'FAIL A updated B outcome'; end if;
  delete from public.activities where id = 'bbbbbbbb-0000-0000-0000-000000000001';
  get diagnostics n = row_count;  if n <> 0 then raise exception 'FAIL A deleted B activity'; end if;

  begin
    insert into public.activities (participant_id, name, category, duration_min, location, priority)
      values ('bbbbbbbb-0000-0000-0000-00000000000b', 'x', 'x', 1, 'anywhere', 1);
    raise exception 'FAIL A inserted an activity as B';
  exception when insufficient_privilege then null; end;

  begin
    insert into public.outcomes (participant_id, set_id, none_reason)
      values ('bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-0000-0000-0000-000000000003', 'x');
    raise exception 'FAIL A inserted an outcome as B';
  exception when insufficient_privilege or unique_violation then null; end;

  begin  -- own participant id but B's set: composite foreign key rejects it
    insert into public.outcomes (set_id, none_reason) values ('bbbbbbbb-0000-0000-0000-000000000003', 'x');
    raise exception 'FAIL A attached an outcome to B set';
  exception when foreign_key_violation or unique_violation then null; end;

  -- participants cannot write sets/suggestions or read the hidden source columns
  begin
    insert into public.suggestions (set_id, sources, title, description, duration_min, position)
      values ('aaaaaaaa-0000-0000-0000-000000000003', array['A'], 't', 'd', 5, 2);
    raise exception 'FAIL A wrote a suggestion';
  exception when insufficient_privilege then null; end;
  begin
    perform sources from public.suggestions;
    raise exception 'FAIL A can read suggestions.sources';
  exception when insufficient_privilege then null; end;
  begin
    perform activity_id from public.suggestions;
    raise exception 'FAIL A can read suggestions.activity_id';
  exception when insufficient_privilege then null; end;
  begin
    perform history_summary from public.suggestion_sets;
    raise exception 'FAIL A can read history_summary';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.export_suggestions;
    raise exception 'FAIL A can read the export view';
  exception when insufficient_privilege then null; end;
end $$;

-- ===== signed out (anon) =====
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  begin perform 1 from public.profiles;   raise exception 'FAIL anon read profiles';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.activities; raise exception 'FAIL anon read activities';
  exception when insufficient_privilege then null; end;
  begin perform 1 from public.outcomes;   raise exception 'FAIL anon read outcomes';
  exception when insufficient_privilege then null; end;
end $$;

reset role;
rollback;
select 'RLS checks passed' as result;
