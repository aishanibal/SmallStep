// Hard filters applied in code to ALL sources: waking hours, quiet hours, fit the gap, meal windows.
import { localMinuteOfDay, mod, parseClock } from "./time.ts";
import { MEAL_RULES, type MealRules } from "./filters.config.ts";
import type { Activity, Gap, Profile } from "./types.ts";

export type Rejection = "too_long" | "outside_waking_hours" | "quiet_hours" | "after_meal";
export type Verdict = { ok: true } | { ok: false; reason: Rejection };

export interface Candidate {
  durationMin: number;
  /** Known for Sources A and C. Source B has none and is checked by keywords instead. */
  category?: string | null;
  /** Title and description, used only when there is no category. */
  text?: string;
}

/** True if [start, start+len) overlaps the daily-repeating window [winStart, winStart+winLen). Minutes of day. */
function overlapsDaily(start: number, len: number, winStart: number, winLen: number): boolean {
  if (winLen <= 0) return false;
  const offset = mod(start - winStart, 1440);
  return offset < winLen || offset + len > 1440;
}

function isHighIntensity(c: Candidate, rules: MealRules): boolean {
  if (c.category) return rules.highIntensityCategories.includes(c.category.trim().toLowerCase());
  const text = (c.text ?? "").toLowerCase();
  return rules.highIntensityKeywords.some((k) => text.includes(k));
}

/** Check one candidate that would start at the gap's start. */
export function checkCandidate(
  c: Candidate,
  gap: Gap,
  profile: Profile,
  rules: MealRules = MEAL_RULES,
): Verdict {
  if (c.durationMin > gap.minutes) return { ok: false, reason: "too_long" };

  const start = localMinuteOfDay(gap.start, profile.timezone);
  const len = c.durationMin;

  // Must sit inside wake -> bedtime (which may run past midnight).
  const wake = parseClock(profile.wake);
  const awakeLen = mod(parseClock(profile.bedtime) - wake, 1440) || 1440;
  if (mod(start - wake, 1440) + len > awakeLen) return { ok: false, reason: "outside_waking_hours" };

  // Must not touch quiet hours (start == end means none).
  const quietStart = parseClock(profile.quiet_start);
  const quietLen = mod(parseClock(profile.quiet_end) - quietStart, 1440);
  if (overlapsDaily(start, len, quietStart, quietLen)) return { ok: false, reason: "quiet_hours" };

  if (isHighIntensity(c, rules)) {
    for (const meal of [profile.breakfast, profile.lunch, profile.dinner]) {
      if (overlapsDaily(start, len, parseClock(meal), rules.minutesAfterMeal)) {
        return { ok: false, reason: "after_meal" };
      }
    }
  }
  return { ok: true };
}

/** The activity's duration if it passes every filter for this gap, otherwise null. */
export function pickDuration(
  a: Activity,
  gap: Gap,
  profile: Profile,
  rules: MealRules = MEAL_RULES,
): number | null {
  return checkCandidate({ durationMin: a.duration_min, category: a.category }, gap, profile, rules).ok ? a.duration_min : null;
}

/** Longest shorter version (at least 5 minutes) of the activity that passes every filter, or null. */
export function shortenedDuration(
  a: Activity,
  gap: Gap,
  profile: Profile,
  rules: MealRules = MEAL_RULES,
): number | null {
  for (let d = Math.min(a.duration_min, gap.minutes); d >= 5; d--) {
    if (checkCandidate({ durationMin: d, category: a.category }, gap, profile, rules).ok) return d;
  }
  return null;
}

/** The participant's activities that can be suggested for this gap, each with the duration to show.
 *  Activities that fit at their usual length come first; only if none does are shortened versions offered. */
export function allowedActivities(
  activities: Activity[],
  gap: Gap,
  profile: Profile,
  rules: MealRules = MEAL_RULES,
): { activity: Activity; durationMin: number }[] {
  const collect = (pick: (a: Activity) => number | null) =>
    activities.flatMap((activity) => {
      const durationMin = pick(activity);
      return durationMin === null ? [] : [{ activity, durationMin }];
    });
  const full = collect((a) => pickDuration(a, gap, profile, rules));
  return full.length > 0 ? full : collect((a) => shortenedDuration(a, gap, profile, rules));
}
