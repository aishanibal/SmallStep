-- One row per suggestion with set, gap, and outcome fields, for CSV export from the dashboard.
-- Query it in the SQL editor (runs as postgres). Closed to app users: invoker rights + no grants.
create view public.export_suggestions with (security_invoker = true) as
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
  o.ts                                                          as outcome_ts            -- UTC
from public.suggestions sg
join public.suggestion_sets ss on ss.id = sg.set_id
join public.profiles p         on p.id = ss.participant_id
join auth.users u              on u.id = ss.participant_id
join public.gaps g             on g.id = ss.gap_id
left join public.activities a  on a.id = sg.activity_id
left join public.outcomes o    on o.set_id = ss.id;

revoke all on public.export_suggestions from anon, authenticated;
