# SmallStep

A learning prototype for CS 4261. An iOS app (SwiftUI) backed by Supabase that tests one hypothesis:

> Suggestions built from a person's schedule gaps, daily rhythm, own wellness activities, and history of
> completions and skips get chosen and completed more often than generic suggestions.

Each time a participant asks for ideas for a gap, they see three cards in the same format, in shuffled order,
with the source hidden:

| Source | What it is |
| --- | --- |
| **A** context | Gemini writes one suggestion tailored to the participant: one of their activities, an adapted version, or a new idea in the same spirit. It gets the gap, time of day and weekday, energy, rhythm, wellness statement, their activities, and a history summary built by code (completion by slot, fit ratings, skip and "none of these" reasons, weekly intentions, recency, last events) |
| **B** generic | Gemini gets only "I have N minutes and energy E. What should I do for my wellness?" |
| **C** static | A random fitting activity from the participant's list. No model call |

The real product would only have A. B and C exist so the three can be compared.

## Repository layout

```
supabase/
  config.toml            auth + function settings (email confirmation off, verify_jwt on)
  migrations/            schema, Row Level Security, export view
  seed.sql               fake participants for development
  tests/rls_check.sql    RLS check you run in the dashboard (rolls back, keeps nothing)
  tests/local/stub.sql   stand-in for Supabase's auth schema (used by scripts/check-sql.sh only)
  functions/
    _shared/             filters, history summary, prompts, Gemini client, sources A/B/C (+ Deno tests)
    suggest/             builds the three cards for a gap
    dev-info/            feeds the hidden developer screen
ios/
  project.yml            XcodeGen definition (the .xcodeproj is generated, not committed)
  Config.example.xcconfig  copy to Config.local.xcconfig (git-ignored)
  SmallStep/             app: App, Core, Theme, Features (Consent, Auth, Setup, Home, Gap, Suggestions, Outcome, Dev)
  SmallStepTests/        unit tests (ICS parser, gap finder, models)
docs/
  export.sql             export + per-source analysis queries
  YOUR-TODO.md           running checklist of manual steps
scripts/
  check-sql.sh           applies migrations + seed on a throwaway Postgres (Docker) and runs the RLS check
  probe-auth.sh          checks the project accepts the synthetic participant emails
  gen_colors.py          writes the colour tokens and checks their contrast
```

## What you need

- A [Supabase](https://supabase.com) project (free tier is fine) and a Gemini API key
- A Mac with Xcode 16 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- The Supabase CLI (`brew install supabase/tap/supabase`)
- To run the tests: [Deno](https://deno.com) (`brew install deno`) and, for the SQL check, Docker

## 1. Supabase project setup

1. **Create the project** in the dashboard. Note the project ref (the part of `https://<ref>.supabase.co`).
2. **Turn email confirmation off**: Authentication → Sign In / Providers → Email → switch **Confirm email** off.
   Participants have no real email, so nobody could click a confirmation link.
3. **Link and push the schema**:
   ```sh
   supabase login
   supabase link --project-ref <ref>
   supabase db push
   ```
4. **Check Row Level Security**: open `supabase/tests/rls_check.sql`, paste it into Dashboard → SQL Editor, run it.
   It ends with `RLS checks passed`. It creates two throwaway users inside a transaction and rolls it back.
5. **Check sign-up works** with the synthetic email domain: `scripts/probe-auth.sh`. It creates one test user
   (`probe-xxxxxx`); delete it afterwards under Authentication → Users. If Supabase rejects the domain, try
   another (`scripts/probe-auth.sh yourdomain.org`) and use that one in the app config (step 1 of section 2).
6. **Set the secrets** (they live only in Supabase; never put them in a file or in chat):
   ```sh
   supabase secrets set GEMINI_API_KEY=<your key> GEMINI_MODEL=<model name>
   ```
   `GEMINI_MODEL` is whichever Gemini model you want for both A and B. Both calls use temperature 0.2.
7. **Deploy the functions**:
   ```sh
   supabase functions deploy suggest
   supabase functions deploy dev-info
   ```
8. Optional: paste `supabase/seed.sql` into the SQL editor for two fake participants (`seed01`, `seed02`) with
   20 suggestion sets each, handy for trying the export queries before real data exists.

Supabase supplies `SUPABASE_URL` and the service key to the functions itself. The only keys you ever handle are
your Gemini key (a Supabase secret) and the project's public **publishable** key (in the app config).

## 2. Run the iOS app

1. `cp ios/Config.example.xcconfig ios/Config.local.xcconfig` and fill in your project URL, the **publishable**
   key (`sb_publishable_…`), and the email domain that passed `probe-auth.sh`. This file is git-ignored.
   The publishable key is public by design and does end up inside the app. The Gemini key and the Supabase
   secret key must never go here.
2. Generate and open the project:
   ```sh
   cd ios && xcodegen generate && open SmallStep.xcodeproj
   ```
3. In Xcode: select the **SmallStep** target → Signing & Capabilities → choose your **Team** (a free Apple ID works).
   If the bundle identifier `study.smallstep.app` is taken, change it in `ios/project.yml` and regenerate.
4. Pick an iPhone simulator and press Run (⌘R).

First launch: consent → participant code + passcode (6+ characters; a new code is created on first use) →
activities → daily rhythm → home.

### Rebuild and reinstall on a phone

1. Plug the iPhone in and trust the computer. On the phone: Settings → Privacy & Security → **Developer Mode** → on
   (it restarts the phone).
2. In Xcode choose the phone as the run destination and press Run. The first time, on the phone open
   Settings → General → VPN & Device Management → your Apple ID → **Trust**.
3. **Free Apple IDs**: the app stops opening after 7 days. Press Run again from Xcode to reinstall; data is
   unaffected. For a longer study, an Apple Developer Program membership (TestFlight) avoids this.
4. **Reinstall test**: delete the app, press Run again, and sign in with the same code and passcode. Activities,
   rhythm and history come back, because everything lives under the same `auth.uid()` in Supabase. (The consent
   screen shows again on a fresh install.)
5. After pulling changes that touch `ios/project.yml`, run `xcodegen generate` again.

## 3. Run the tests

```sh
deno test supabase/functions/_shared          # history summary, filters, sources A/B/C, Gemini client
./scripts/check-sql.sh                        # migrations + seed + RLS check + export queries (needs Docker)
cd ios && xcodegen generate && xcodebuild -project SmallStep.xcodeproj -scheme SmallStep \
  -destination 'platform=iOS Simulator,name=iPhone 17' test CODE_SIGNING_ALLOWED=NO
```

`check-sql.sh` runs the SQL on a plain Postgres container with a stub of Supabase's `auth` schema. It is a sanity
check, not a substitute for running `rls_check.sql` once on the real project (step 4 above).

## 4. Export data

`docs/export.sql` has the queries; run them in Dashboard → SQL Editor and use **Download CSV** on the result.

- `select * from public.export_suggestions` gives **one row per suggestion** with its set, gap, and outcome fields
  (`chosen`, `completed`, `skip_reason`, `fit_rating`, `none_reason`, `latency_ms`, `error`, …).
- Query 2 gives, per source: share of picks (against the one-third chance level), completion rate of picks.
- Queries 3 and 5 give the "None of these" rate and its reasons; queries 4 and 5 give trends by day.

Notes for analysis: when two sources pick the same activity the card is shown once and `sources` reads `A+C`
(credited to both, so a pick counts for each). `A_fallback` means Source A's model call failed or its output
was invalid and a rule-based pick was used; the `error` column says why. A Source B card with an `error` is a
generic stand-in shown because B's call failed or broke a rule. Timestamps are UTC; `set_local_date` is the day in
the participant's own time zone.

## 5. Privacy and safety design

- **No personal information.** Login is a participant code + passcode, mapped to `code@<domain>`. Nothing else
  identifying is collected, and no sleep, weight, calories or mood.
- **Row Level Security is on for every table.** A participant can only read and write their own rows (checked by
  `rls_check.sql`). Participants cannot write suggestion sets or suggestions at all; only the `suggest` function can.
- **The source is hidden at the database level too.** Participants can't read `sources`, `activity_id`,
  `reason_text`, `prompt_snapshot`, `model`, `latency_ms`, `error` or the stored history summary. Consequently the
  app names the columns it wants; `select *` on `suggestions` or `suggestion_sets` is denied.
- **What Gemini receives**: gap minutes, time of day, optional energy, activity names and categories, rhythm
  summary, the wellness statement, and the history summary (Source A); only gap minutes and energy (Source B).
  Never calendar event titles or anything identifying. Calendar files are parsed on the phone; only the free gap
  you pick (start and minutes) is saved.
- **Hard filters in code for all three sources**: stay within waking hours, respect quiet hours, fit the gap, and
  the meal-window rule. The meal rule (default: nothing high-intensity within 60 minutes after a meal) lives only in
  `supabase/functions/_shared/filters.config.ts`.
- **Soft preferences only reach Source A.**
- **Source A's output** is validated like B's (whole JSON, fits the gap, passes the hard filters). Its `based_on`
  activity, if any, is stored as `activity_id`; its "why it suits you" sentence is stored in `reason_text` and not
  shown, so A's cards read like B's.

## 6. The developer screen

On Home, **long-press the "SmallStep" title** for about a second. It shows the history summary as it would be built
right now, and the last Source A prompt with the summary it contained and whether the model answered or the
fallback ran. Log a few outcomes, reopen it, and the summary changes. The screen never says which card was which source.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| "We couldn't sign you in just now" with an email message | Supabase rejected the email domain. Run `scripts/probe-auth.sh <domain>` |
| Sign-up says it needs an email step | **Confirm email** is still on in the dashboard |
| Ideas never load, 401 in the function logs | Function not deployed, or signed out. Check Edge Functions → Logs |
| Source A always `A_fallback` | Read the `error` column: usually `GEMINI_API_KEY`/`GEMINI_MODEL` not set, or the model name is wrong |
| "permission denied for table suggestions" | Something is using `select *` on a hidden-column table; name the columns |
| "Not connected yet" screen | `ios/Config.local.xcconfig` missing or incomplete; regenerate with `xcodegen generate` |

## Known limits

- Calendar import reads `.ics` files only (no subscribed URLs). It expands common repeating events (daily, weekly
  with days, monthly by date, yearly) and tells the participant when it meets a pattern it can't read. All-day
  events aren't treated as busy. Three days are scanned and gaps over 8 hours are capped at 8.
- The setup stopwatch measures wall-clock time from first showing setup to finishing it, including breaks.
- Gemini's `generateContent` endpoint is used. Google calls it "legacy" but fully supported.
