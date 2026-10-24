-- SmallStep schema. All timestamps are timestamptz (stored in UTC).
-- participant id = auth.uid(); profiles.id is that uuid.

create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  -- Daily rhythm: local clock times in `timezone`. Null until the rhythm screen is saved.
  wake                time,
  bedtime             time,
  breakfast           time,
  lunch               time,
  dinner              time,
  quiet_start         time,
  quiet_end           time,
  timezone            text,                 -- IANA name, e.g. America/New_York
  wellness_statement  text check (char_length(wellness_statement) <= 300),
  setup_seconds       integer check (setup_seconds >= 0),
  consented_at        timestamptz,          -- when the consent screen was accepted
  created_at          timestamptz not null default now()
);

create table public.activities (
  id               uuid primary key default gen_random_uuid(),
  participant_id   uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name             text not null check (char_length(name) between 1 and 60),
  category         text not null check (char_length(category) between 1 and 40),
  short_min        integer not null check (short_min between 1 and 240),
  long_min         integer not null check (long_min between 1 and 240),
  location         text not null check (location in ('indoors', 'outdoors', 'anywhere')),
  priority         smallint not null check (priority between 1 and 3),
  weekly_intention smallint check (weekly_intention between 1 and 14),  -- null = "whenever"
  created_at       timestamptz not null default now(),
  check (long_min >= short_min)
);
create index activities_participant_idx on public.activities (participant_id);

create table public.gaps (
  id              uuid primary key default gen_random_uuid(),
  participant_id  uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  start_time      timestamptz not null,
  minutes         integer not null check (minutes between 5 and 480),
  energy          smallint check (energy between 1 and 3),
  created_at      timestamptz not null default now()
);
create index gaps_participant_idx on public.gaps (participant_id, start_time);

-- Written only by the `suggest` Edge Function (service role).
create table public.suggestion_sets (
  id               uuid primary key default gen_random_uuid(),
  participant_id   uuid not null references public.profiles (id) on delete cascade,
  gap_id           uuid not null references public.gaps (id) on delete cascade,
  history_summary  text,              -- what Source A saw; hidden from participants
  created_at       timestamptz not null default now(),
  unique (id, participant_id)
);
create index suggestion_sets_participant_idx on public.suggestion_sets (participant_id, created_at);

-- Written only by the `suggest` Edge Function (service role).
-- `sources` has more than one entry when two sources picked the same activity (credit both).
create table public.suggestions (
  id                uuid primary key default gen_random_uuid(),
  set_id            uuid not null references public.suggestion_sets (id) on delete cascade,
  sources           text[] not null
                      check (cardinality(sources) between 1 and 3
                             and sources <@ array['A', 'A_fallback', 'B', 'C']),
  activity_id       uuid references public.activities (id) on delete set null,  -- null for Source B
  title             text not null,
  description       text not null,
  duration_min      integer not null check (duration_min > 0),
  position          smallint not null check (position between 0 and 2),
  reason_text       text,
  prompt_snapshot   text,
  model             text,
  latency_ms        integer,
  error             text,
  unique (set_id, position),
  unique (set_id, id)
);

-- One row per set: created when the participant chooses a card (or "None of these"),
-- then updated with completed / skip_reason / fit_rating.
create table public.outcomes (
  id                    uuid primary key default gen_random_uuid(),
  participant_id        uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  set_id                uuid not null,
  chosen_suggestion_id  uuid,
  none_reason           text,
  completed             boolean,      -- null = chosen, not resolved yet; true = done; false = skipped
  skip_reason           text,
  fit_rating            smallint check (fit_rating between 1 and 5),
  ts                    timestamptz not null default now(),
  unique (set_id),
  -- the set must be this participant's, and the chosen card must belong to the set
  foreign key (set_id, participant_id) references public.suggestion_sets (id, participant_id) on delete cascade,
  foreign key (set_id, chosen_suggestion_id) references public.suggestions (set_id, id) on delete cascade,
  check (chosen_suggestion_id is null or none_reason is null),
  check (chosen_suggestion_id is not null or (completed is null and skip_reason is null and fit_rating is null))
);
create index outcomes_participant_idx on public.outcomes (participant_id, ts);

-- Every new auth user gets an empty profile; the app fills it in during setup.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
