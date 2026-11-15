-- Sprint 4, phase 1.
--   1. Transition time: minutes each participant wants free before their next commitment (default 5).
--   2. Generation tracking: whether each card came from the model, a fallback, or the participant's own list.
--   3. Suggestion variety: repeated or near-identical cards are flagged for analysis only (nothing in the app changes).

-- 1. Transition time. Suggestions must fit in gap minutes minus this.
alter table public.profiles
  add column transition_min smallint not null default 5 check (transition_min between 0 and 30);

-- 2. Generation. 'model' = Gemini answered and passed the filters; 'fallback' = A_fallback or B's generic idea
--    after the model failed or broke a rule (the reason is in `error`); 'list' = Source C, no model involved.
--    Not granted to participants (blind study): the column-level grants in the RLS migration still apply.
alter table public.suggestions
  add column generation text check (generation in ('model', 'fallback', 'list'));

-- Backfill rows written before this column existed. Same rule the Edge Function now applies.
update public.suggestions set generation = case
  when sources = array['C']         then 'list'
  when 'A_fallback' = any (sources) then 'fallback'
  when error is not null            then 'fallback'
  else 'model'
end
where generation is null;

-- 3. Variety, computed from what was stored, so it also covers suggestions made before this migration.
--    "Similar" titles use the same rule as tooClose() in suggest_core.ts: after lowercasing and keeping only
--    letters and digits, one title equals or contains the other.
--    repeat_flag   'same_activity'  the same activity was shown in one of the participant's previous 3 sets
--                  'similar_title'  otherwise, a near-identical title was shown in one of those sets
--    similar_in_set                 another card in the same set has the same activity or a near-identical title
create view public.suggestion_variety with (security_invoker = true) as
with s as (
  select sg.id, sg.set_id, ss.participant_id, sg.activity_id,
         trim(regexp_replace(lower(sg.title), '[^a-z0-9]+', ' ', 'g')) as norm,
         dense_rank() over (partition by ss.participant_id order by ss.created_at, ss.id) as set_n
  from public.suggestions sg
  join public.suggestion_sets ss on ss.id = sg.set_id
)
select
  cur.id as suggestion_id,
  case
    when cur.activity_id is not null and exists (
      select 1 from s prev
      where prev.participant_id = cur.participant_id and prev.set_n between cur.set_n - 3 and cur.set_n - 1
        and prev.activity_id = cur.activity_id) then 'same_activity'
    when cur.norm <> '' and exists (
      select 1 from s prev
      where prev.participant_id = cur.participant_id and prev.set_n between cur.set_n - 3 and cur.set_n - 1
        and prev.norm <> '' and (strpos(prev.norm, cur.norm) > 0 or strpos(cur.norm, prev.norm) > 0)) then 'similar_title'
  end as repeat_flag,
  exists (
    select 1 from s other
    where other.set_id = cur.set_id and other.id <> cur.id
      and ((cur.activity_id is not null and other.activity_id = cur.activity_id)
           or (cur.norm <> '' and other.norm <> ''
               and (strpos(other.norm, cur.norm) > 0 or strpos(cur.norm, other.norm) > 0)))
  ) as similar_in_set
from s cur;

revoke all on public.suggestion_variety from anon, authenticated;

-- Export: same columns as before, with the new ones added at the end (create or replace can only append).
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
  v.similar_in_set
from public.suggestions sg
join public.suggestion_sets ss on ss.id = sg.set_id
join public.profiles p         on p.id = ss.participant_id
join auth.users u              on u.id = ss.participant_id
join public.gaps g             on g.id = ss.gap_id
left join public.activities a  on a.id = sg.activity_id
left join public.outcomes o    on o.set_id = ss.id
left join public.suggestion_variety v on v.suggestion_id = sg.id;

revoke all on public.export_suggestions from anon, authenticated;
