-- SmallStep export queries. Run in Dashboard -> SQL Editor; use "Download CSV" on the result grid.
-- Source view: public.export_suggestions (one row per suggestion, outcome fields attached).
--
-- Column notes
--   sources        'A', 'A_fallback', 'B', 'C', or a combination such as 'A+C' when two sources picked
--                  the same activity (the card is shown once and credited to both).
--   answered       the participant chose a card or "None of these" for this set.
--   chosen         this suggestion is the card they picked.
--   completed      only filled on the chosen card: true = done, false = skipped, null = not resolved yet.
--   set_local_date the day in the participant's own time zone; timestamps are UTC.

-- 1. Raw export: one row per suggestion.
select * from public.export_suggestions order by participant_code, set_created_at, position;

-- 2. Per source, overall.
--    Credited sources are unnested, so a shared card counts for each source that picked it.
--    Every set shows each of A, B, C once, so with no preference share_of_picks is about 1/3
--    (a little higher when cards are shared, because one pick is credited to two sources).
--    A_fallback is its own row; add it to A yourself if you want "A as delivered".
with answered as (
  select set_id, bool_or(chosen) as has_pick
  from public.export_suggestions where answered group by set_id
),
totals as (
  select count(*) filter (where has_pick) as total_picks, count(*) as answered_sets,
         count(*) filter (where not has_pick) as none_sets
  from answered
),
per_source as (
  select src.source,
         count(*)                                           as times_shown,
         count(*) filter (where e.chosen)                   as picks,
         count(*) filter (where e.chosen and e.completed is not null) as resolved_picks,
         count(*) filter (where e.chosen and e.completed)   as completed_picks
  from public.export_suggestions e
  cross join lateral unnest(e.sources_array) as src(source)
  where e.answered
  group by src.source
)
select p.source,
       p.times_shown,
       p.picks,
       round(p.picks::numeric / nullif(t.total_picks, 0), 3)           as share_of_picks,
       round(1.0 / 3, 3)                                               as chance_share,
       p.resolved_picks,
       round(p.completed_picks::numeric / nullif(p.resolved_picks, 0), 3) as completion_rate
from per_source p cross join totals t
order by p.source;

-- 3. "None of these" rate, overall and its reasons.
select count(*) filter (where set_none_chosen) / count(*)::numeric as none_rate_of_sets, count(*) as answered_sets
from (select distinct set_id, set_none_chosen from public.export_suggestions where answered) s;

select none_reason, count(*) as sets
from (select distinct set_id, none_reason from public.export_suggestions where set_none_chosen) s
group by none_reason order by sets desc;

-- 4. Trend by day (participant-local date), per source.
with day_picks as (
  select set_local_date, count(distinct set_id) filter (where chosen) as total_picks
  from public.export_suggestions where answered group by set_local_date
)
select e.set_local_date as day, src.source,
       count(*) filter (where e.chosen)                                       as picks,
       round(count(*) filter (where e.chosen)::numeric / nullif(d.total_picks, 0), 3) as share_of_picks,
       count(*) filter (where e.chosen and e.completed)                       as completed_picks,
       count(*) filter (where e.chosen and e.completed is not null)           as resolved_picks
from public.export_suggestions e
cross join lateral unnest(e.sources_array) as src(source)
join day_picks d using (set_local_date)
where e.answered
group by e.set_local_date, src.source, d.total_picks
order by day, src.source;

-- 5. None-rate by day.
select set_local_date as day,
       count(*) filter (where set_none_chosen) as none_sets,
       count(*) as answered_sets
from (select distinct set_id, set_local_date, set_none_chosen from public.export_suggestions where answered) s
group by set_local_date order by day;
