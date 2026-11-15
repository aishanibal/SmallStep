-- Sprint 4, phase 4: manual reminder windows.
-- A student lists their usual free times (e.g. Mondays 14:00 for 45 minutes). The phone sends a nudge when
-- one starts, without a calendar. Gaps now say where they came from, so the study can compare sets started
-- from a nudge with sets the student started by opening the app.

-- Windows are never deleted by the app, only marked removed, so analysis can see what was set and when.
create table public.reminder_windows (
  id              uuid primary key default gen_random_uuid(),
  participant_id  uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  weekday         smallint not null check (weekday between 1 and 7),     -- ISO: 1 = Monday ... 7 = Sunday
  start_time      time not null,                                          -- local, in profiles.timezone
  minutes         smallint not null check (minutes between 10 and 480),
  created_at      timestamptz not null default now(),
  removed_at      timestamptz
);
create index reminder_windows_participant_idx on public.reminder_windows (participant_id);

alter table public.reminder_windows enable row level security;
create policy reminder_windows_select on public.reminder_windows for select to authenticated
  using (participant_id = (select auth.uid()));
create policy reminder_windows_insert on public.reminder_windows for insert to authenticated
  with check (participant_id = (select auth.uid()));
create policy reminder_windows_update on public.reminder_windows for update to authenticated
  using (participant_id = (select auth.uid())) with check (participant_id = (select auth.uid()));
revoke all on public.reminder_windows from anon;
revoke delete on public.reminder_windows from authenticated;

-- Where a gap came from. Null on rows from before this.
--   manual           "Get suggestions", starting now
--   calendar         picked from the uploaded calendar
--   window_reminder  opened from a free-time nudge (window_id says which)
alter table public.gaps
  add column origin    text check (origin in ('manual', 'calendar', 'window_reminder')),
  add column window_id uuid references public.reminder_windows (id) on delete set null;

-- A gap may only point at the participant's own window.
drop policy gaps_insert on public.gaps;
create policy gaps_insert on public.gaps for insert to authenticated
  with check (participant_id = (select auth.uid())
              and (window_id is null or exists (select 1 from public.reminder_windows w
                                                where w.id = window_id and w.participant_id = (select auth.uid()))));

-- Reminder events can now be about a window (the student tapped a nudge) as well as an outcome.
alter table public.reminder_events
  alter column outcome_id drop not null,
  add column window_id uuid references public.reminder_windows (id) on delete cascade,
  add constraint reminder_events_about_one check (num_nonnulls(outcome_id, window_id) = 1);

drop policy reminder_events_insert on public.reminder_events;
create policy reminder_events_insert on public.reminder_events for insert to authenticated
  with check (participant_id = (select auth.uid())
              and (outcome_id is null or exists (select 1 from public.outcomes o
                                                 where o.id = outcome_id and o.participant_id = (select auth.uid())))
              and (window_id is null or exists (select 1 from public.reminder_windows w
                                                where w.id = window_id and w.participant_id = (select auth.uid()))));

-- Export: everything from before, plus where the gap came from.
create or replace view public.export_suggestions with (security_invoker = true) as
select
  split_part(u.email, '@', 1)                                   as participant_code,
  ss.participant_id,
  ss.id                                                         as set_id,
  sg.id                                                         as suggestion_id,
  ss.created_at                                                 as set_created_at,       -- UTC
  (ss.created_at at time zone coalesce(p.timezone, 'UTC'))::date as set_local_date,
  g.start_time                                                  as gap_start_time,       -- UTC
  g.minutes                                                     as gap_minutes,
  g.energy                                                      as gap_energy,
  sg.position,
  array_to_string(sg.sources, '+')                              as sources,              -- e.g. 'A', 'A+C', 'A_fallback'
  sg.sources                                                    as sources_array,
  sg.activity_id,
  a.category                                                    as activity_category,
  a.priority                                                    as activity_priority,
  sg.title,
  sg.duration_min,
  sg.reason_text,
  sg.model,
  sg.latency_ms,
  sg.error,
  (o.id is not null)                                            as answered,             -- set got a choice or "none"
  (o.chosen_suggestion_id = sg.id)                              as chosen,
  (o.id is not null and o.chosen_suggestion_id is null)         as set_none_chosen,
  o.none_reason,
  case when o.chosen_suggestion_id = sg.id then o.completed end   as completed,
  case when o.chosen_suggestion_id = sg.id then o.skip_reason end as skip_reason,
  case when o.chosen_suggestion_id = sg.id then o.fit_rating end  as fit_rating,
  o.ts                                                          as outcome_ts,           -- UTC
  sg.generation,                                                                         -- model / fallback / list
  p.transition_min,                                                                      -- participant's current setting
  v.repeat_flag,
  v.similar_in_set,
  o.via                                                         as outcome_via,          -- app / reminder
  r.reminder_status,                                                                     -- scheduled / suppressed / null
  r.reminder_suppressed_why,
  coalesce(r.reminder_snoozes, 0)                               as reminder_snoozes,
  r.reminder_first_response,                                                             -- opened / done / skip / snoozed
  g.origin                                                      as gap_origin            -- manual / calendar / window_reminder
from public.suggestions sg
join public.suggestion_sets ss on ss.id = sg.set_id
join public.profiles p         on p.id = ss.participant_id
join auth.users u              on u.id = ss.participant_id
join public.gaps g             on g.id = ss.gap_id
left join public.activities a  on a.id = sg.activity_id
left join public.outcomes o    on o.set_id = ss.id
left join public.suggestion_variety v on v.suggestion_id = sg.id
left join lateral (
  select
    case when bool_or(e.kind = 'scheduled') then 'scheduled'
         when bool_or(e.kind = 'suppressed') then 'suppressed' end                    as reminder_status,
    (array_agg(e.detail order by e.at) filter (where e.kind = 'suppressed'))[1]       as reminder_suppressed_why,
    count(*) filter (where e.kind = 'snoozed')                                        as reminder_snoozes,
    (array_agg(e.kind order by e.at)
       filter (where e.kind in ('opened', 'done', 'skip', 'snoozed')))[1]             as reminder_first_response
  from public.reminder_events e
  where e.outcome_id = o.id
) r on true;

revoke all on public.export_suggestions from anon, authenticated;
