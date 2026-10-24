-- Fake participants for development. Run in the dashboard SQL editor (or `supabase db reset` locally).
-- Idempotent: re-running does nothing if seed01 already exists.
-- Sign-in for these accounts is unverified on hosted projects; they exist mainly to exercise the
-- history summary, RLS, and the export view. Change the email domain to match the app's.

do $$
declare
  codes text[] := array['seed01', 'seed02'];
  uid uuid;
  code text;
  acts uuid[];
  a_names text[] := array['Morning walk', 'Gentle stretch', 'Breathing pause', 'Strength circuit'];
  a_cats  text[] := array['movement', 'yoga', 'mindfulness', 'strength'];
  a_dur   int[]  := array[20, 10, 5, 15];
  a_loc   text[] := array['outdoors', 'anywhere', 'anywhere', 'indoors'];
  a_prio  int[]  := array[3, 2, 2, 1];
  a_week  int[]  := array[4, 3, null, 2];
  perms int[][] := array[[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]];
  srcs text[] := array['A', 'B', 'C'];
  i int; k int; gap_id uuid; set_id uuid; sug_ids uuid[]; chosen int; r float;
  a_idx int; c_idx int; hours int[] := array[7, 9, 12, 15, 18, 20]; mins int[] := array[10, 20, 30, 45, 60];
  g_min int; g_start timestamptz; src text; done boolean;
begin
  perform setseed(0.42);
  foreach code in array codes loop
    continue when exists (select 1 from auth.users where email = code || '@study.example');
    uid := gen_random_uuid();

    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change, email_change_token_new)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
            code || '@study.example', extensions.crypt('seedpass1', extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider,
                                 last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', code || '@study.example'),
            'email', now(), now(), now());

    -- profile row already exists (created by trigger)
    update public.profiles set
      wake = '07:00', bedtime = '23:00', breakfast = '08:00', lunch = '12:30', dinner = '19:00',
      quiet_start = '22:00', quiet_end = '07:00', timezone = 'America/New_York',
      wellness_statement = 'Feeling steady and unhurried.', setup_seconds = 240, consented_at = now()
    where id = uid;

    acts := array[]::uuid[];
    for k in 1..4 loop
      acts := acts || gen_random_uuid();
      insert into public.activities (id, participant_id, name, category, duration_min,
                                     location, priority, weekly_intention)
      values (acts[k], uid, a_names[k], a_cats[k], a_dur[k], a_loc[k], a_prio[k], a_week[k]);
    end loop;

    for i in 1..20 loop
      g_min := mins[1 + (i % 5)];
      g_start := date_trunc('day', now()) - ((20 - i) * interval '16 hours')
                 + (hours[1 + (i % 6)] * interval '1 hour');
      gap_id := gen_random_uuid(); set_id := gen_random_uuid();
      insert into public.gaps (id, participant_id, start_time, minutes, energy, created_at)
      values (gap_id, uid, g_start, g_min, 1 + (i % 3), g_start);
      insert into public.suggestion_sets (id, participant_id, gap_id, created_at)
      values (set_id, uid, gap_id, g_start);

      a_idx := 1 + floor(random() * 4)::int;
      c_idx := 1 + floor(random() * 4)::int;
      sug_ids := array[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()];
      for k in 1..3 loop
        -- position of source k in this set
        src := srcs[k];
        insert into public.suggestions (id, set_id, sources, activity_id, title, description,
                                        duration_min, position, model, latency_ms)
        values (sug_ids[k], set_id, array[src],
                case src when 'A' then acts[a_idx] when 'C' then acts[c_idx] end,
                case src when 'A' then a_names[a_idx] when 'C' then a_names[c_idx] else 'Look out a window' end,
                'Seeded example card.',
                least(g_min, case src when 'A' then a_dur[a_idx] when 'C' then a_dur[c_idx] else 5 end),
                perms[1 + (i % 6)][k], case when src = 'C' then null else 'seed-model' end,
                case when src = 'C' then null else 800 + i * 20 end);
      end loop;

      r := random();
      if r < 0.15 then
        insert into public.outcomes (participant_id, set_id, none_reason, ts)
        values (uid, set_id, (array['not_now', 'not_interested', 'wrong_length'])[1 + (i % 3)], g_start);
      else
        chosen := case when r < 0.55 then 1 when r < 0.80 then 3 else 2 end;   -- index into srcs
        done := random() < case chosen when 1 then 0.8 when 2 then 0.6 else 0.5 end;
        insert into public.outcomes (participant_id, set_id, chosen_suggestion_id, completed,
                                     skip_reason, fit_rating, ts)
        values (uid, set_id, sug_ids[chosen], done,
                case when done then null else (array['no_energy', 'ran_out_of_time', 'changed_my_mind'])[1 + (i % 3)] end,
                case when done then 3 + (i % 3) else 1 + (i % 3) end, g_start + interval '5 minutes');
      end if;
    end loop;
  end loop;
end $$;
