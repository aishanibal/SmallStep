-- Sprint 4, phase 5: weekly progress.
-- Participants can't read suggestions.activity_id (blind study), so the app can't tell which of their
-- activities a completed card counted toward. This function returns only per-activity totals of
-- completed outcomes for one week: no sources, no card ids. A null activity_id groups ideas that were
-- not tied to one of their activities, and activities that were removed since.
create function public.weekly_progress(week_start timestamptz)
returns table (activity_id uuid, done integer)
language sql stable security definer set search_path = '' as $$
  select sg.activity_id, count(*)::integer
  from public.outcomes o
  join public.suggestions sg on sg.id = o.chosen_suggestion_id
  where o.participant_id = (select auth.uid())
    and o.completed = true
    and o.ts >= week_start and o.ts < week_start + interval '7 days'
  group by sg.activity_id
$$;

revoke all on function public.weekly_progress(timestamptz) from public, anon;
grant execute on function public.weekly_progress(timestamptz) to authenticated;
