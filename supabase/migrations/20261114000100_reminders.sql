-- Sprint 4, phases 2 and 3: reminder controls and outcome reminders.
-- Reminders are local notifications scheduled on the phone. The database keeps the settings (so the study
-- can see who paused or capped them) and a log of what happened to each reminder.

-- Controls. Quiet hours reuse profiles.quiet_start / quiet_end, which already mean "leave me alone".
alter table public.profiles
  add column reminders_on           boolean  not null default true,
  add column reminder_daily_cap     smallint not null default 3 check (reminder_daily_cap between 1 and 10),
  add column reminders_paused_until timestamptz;           -- null = not paused

-- Where Done/Skip was recorded: in the app, or after opening a reminder. Null on rows from before this.
alter table public.outcomes
  add column via text check (via in ('app', 'reminder'));

-- One row per thing that happened to an outcome reminder. Written by the app, possibly later than `at`
-- (a snooze tapped from the lock screen is queued and sent the next time the app opens), so `id` comes
-- from the phone and a resend is ignored.
--   scheduled   a reminder was set for this outcome
--   suppressed  it was not set; detail says why (off, paused, daily_cap, no_permission)
--   opened      the student tapped the reminder itself
--   done / skip the student tapped Done or Skip on it (the app then opens to finish logging)
--   snoozed     Snooze was tapped; this does not count as an outcome
create table public.reminder_events (
  id              uuid primary key,
  participant_id  uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  outcome_id      uuid not null references public.outcomes (id) on delete cascade,
  kind            text not null check (kind in ('scheduled', 'suppressed', 'opened', 'done', 'skip', 'snoozed')),
  detail          text check (char_length(detail) <= 40),
  at              timestamptz not null,                     -- when it happened on the phone
  created_at      timestamptz not null default now()
);
create index reminder_events_outcome_idx on public.reminder_events (outcome_id);

alter table public.reminder_events enable row level security;
create policy reminder_events_select on public.reminder_events for select to authenticated
  using (participant_id = (select auth.uid()));
create policy reminder_events_insert on public.reminder_events for insert to authenticated
  with check (participant_id = (select auth.uid())
              and exists (select 1 from public.outcomes o
                          where o.id = outcome_id and o.participant_id = (select auth.uid())));
revoke all on public.reminder_events from anon;

-- Export: everything from before, plus reminder columns at the end (per set; the same on each of its rows).
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
  r.reminder_first_response                                                              -- opened / done / skip / snoozed
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
