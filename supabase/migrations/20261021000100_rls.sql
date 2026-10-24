-- Row Level Security: a participant can only see and change their own rows.
-- The service role (used by the `suggest` Edge Function and the dashboard) bypasses RLS.

alter table public.profiles         enable row level security;
alter table public.activities       enable row level security;
alter table public.gaps             enable row level security;
alter table public.suggestion_sets  enable row level security;
alter table public.suggestions      enable row level security;
alter table public.outcomes         enable row level security;

-- profiles (created by trigger; no insert or delete from the app)
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- activities
create policy activities_select on public.activities for select to authenticated
  using (participant_id = (select auth.uid()));
create policy activities_insert on public.activities for insert to authenticated
  with check (participant_id = (select auth.uid()));
create policy activities_update on public.activities for update to authenticated
  using (participant_id = (select auth.uid())) with check (participant_id = (select auth.uid()));
create policy activities_delete on public.activities for delete to authenticated
  using (participant_id = (select auth.uid()));

-- gaps
create policy gaps_select on public.gaps for select to authenticated
  using (participant_id = (select auth.uid()));
create policy gaps_insert on public.gaps for insert to authenticated
  with check (participant_id = (select auth.uid()));

-- suggestion_sets / suggestions: read-only for participants
create policy suggestion_sets_select on public.suggestion_sets for select to authenticated
  using (participant_id = (select auth.uid()));
create policy suggestions_select on public.suggestions for select to authenticated
  using (exists (select 1 from public.suggestion_sets s
                 where s.id = set_id and s.participant_id = (select auth.uid())));

-- outcomes
create policy outcomes_select on public.outcomes for select to authenticated
  using (participant_id = (select auth.uid()));
create policy outcomes_insert on public.outcomes for insert to authenticated
  with check (participant_id = (select auth.uid()));
create policy outcomes_update on public.outcomes for update to authenticated
  using (participant_id = (select auth.uid())) with check (participant_id = (select auth.uid()));

-- Blind study: participants must not be able to read which source produced a card.
-- Column-level grants expose only what the cards show. The app must name columns
-- explicitly (select=id,set_id,...) because `select *` would hit a denied column.
revoke all on public.suggestions, public.suggestion_sets from anon, authenticated;
grant select (id, set_id, title, description, duration_min, position)
  on public.suggestions to authenticated;
grant select (id, participant_id, gap_id, created_at)
  on public.suggestion_sets to authenticated;

-- Nothing is readable without signing in.
revoke all on public.profiles, public.activities, public.gaps, public.outcomes from anon;
