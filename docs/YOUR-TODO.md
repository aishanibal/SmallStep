# Your running to-do list

Things only you can do (accounts, secrets, device steps, decisions). Newest phase last. Tick as you go.

## From phase (a): database
- [ ] Install the CLI: `brew install supabase/tap/supabase`
- [ ] `cd` into the repo, then `supabase login` and `supabase link --project-ref cfjbxfxrbyhvlobsdobj`
- [ ] `supabase db push` (applies `supabase/migrations/`)
- [ ] Dashboard -> Authentication -> Sign In / Providers -> Email: turn **Confirm email OFF**
- [ ] Paste `supabase/tests/rls_check.sql` into the SQL editor and run it; it must end with "RLS checks passed"
- [ ] Optional: paste `supabase/seed.sql` into the SQL editor for fake participants (`seed01`, `seed02`)
- [ ] **Rotate the secret key** you pasted in chat (Project Settings -> API Keys). It is not stored anywhere.

## From phase (b)/(c): suggestions
- [ ] `supabase secrets set GEMINI_API_KEY=<your key> GEMINI_MODEL=<model name>` (never paste these into chat or files)
- [ ] `supabase functions deploy suggest`
- [ ] After the app works end to end: check a few `suggestion_sets`/`suggestions` rows in the dashboard. Source A should show `sources = {A}` and `error` null; `{A_fallback}` with an error means Gemini failed (read the error).

## From phase (d): iOS app
(see the bottom of this file once phase (d) is written)
- [ ] Run `scripts/probe-auth.sh` once (it creates one test user, `probe-xxxxxx`, then delete that user in Authentication -> Users). It tells you whether the email domain is accepted and whether "Confirm email" is really off. If the domain is rejected, try another: `scripts/probe-auth.sh yourdomain.org`, then put the one that works in `ios/Config.local.xcconfig` (`PARTICIPANT_EMAIL_DOMAIN`).
- [ ] Build the app yourself once: `brew install xcodegen` (already installed here), then `cd ios && xcodegen generate && open SmallStep.xcodeproj`. In Xcode: select the SmallStep target -> Signing & Capabilities -> pick your Team. Run on a simulator first.
- [ ] Walk the flow once as a new participant: consent -> create code + passcode (6+ characters) -> 3 activities -> day -> gap -> ideas -> choose -> Start -> Done -> rating. Then check the rows in the dashboard.
- [ ] Reinstall test: delete the app, reinstall, sign in with the same code + passcode; your activities and history should be there.
- [ ] Replace the placeholder consent text in `ios/SmallStep/Features/Consent/ConsentView.swift` (marked `PLACEHOLDER TEXT`).
- [ ] Decide: the profile's time zone follows the phone automatically (so clock times stay right when travelling). Say if you'd rather it be fixed at setup.
- [ ] Decide: "Priority 3 matters most" is how the setup screen and the Gemini prompt treat priority. Say if you want it the other way round.
- [ ] `ios/Config.local.xcconfig` is git-ignored and holds the project URL + publishable key. Teammates copy `ios/Config.example.xcconfig` and fill it in.

## From phase (e): .ics import
- [ ] Try it with a real export of your own calendar (Google Calendar: Settings -> Import & export -> Export; Apple Calendar: File -> Export). Get it onto the phone via AirDrop or Files, then Gap screen -> "Or find free time in a calendar file". Check that the free stretches match what you know of your day, especially repeating events.
- [ ] Decide whether all-day events should count as busy. Right now they don't (holidays and birthdays are all-day), and the screen says so.
- [ ] Know the limits (the screen warns the participant when they apply): repeating events like "first Monday of the month" aren't expanded, and unrecognised time-zone names fall back to the phone's. Subscribed calendar URLs aren't supported, only files.
- [ ] Only the next three days are scanned, gaps under 10 minutes are dropped, and a gap longer than 8 hours is capped at 8 hours.

## From phase (f): developer screen, export, README
- [ ] Deploy the second function too: `supabase functions deploy dev-info` (the developer screen needs it).
- [ ] Open the developer screen on the phone (long-press the "SmallStep" title on Home for about a second). After asking for ideas once, check "Last Source A request": it should say "model answered". Log a few outcomes and confirm the history summary changes.
- [ ] Run the queries in `docs/export.sql` in the SQL editor after a few real sessions and download a CSV, to confirm it has what you need for analysis.
- [ ] Read the README top to bottom once; it is the setup guide for your teammates. Fix anything that doesn't match your project.
- [ ] Free Apple IDs: the app expires after 7 days; press Run in Xcode to reinstall. Plan for this if the study is longer than a week (TestFlight needs a paid developer account).
- [ ] Commit when you're happy: nothing in this repo has been committed yet. `ios/Config.local.xcconfig` is git-ignored, so the publishable key stays out of the repo.
