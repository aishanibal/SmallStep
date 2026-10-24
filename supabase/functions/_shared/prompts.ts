// Prompts and output validation for Sources A and B.
// What may leave the system (A): gap minutes, time of day and weekday, optional energy, activity names/categories,
// rhythm summary, wellness statement, history summary. B: gap minutes and optional energy only.
// Calendar event titles never get here: the app sends gaps, not events.
import { checkCandidate } from "./filters.ts";
import { clean } from "./history.ts";
import { localMinuteOfDay, localWeekday, timeOfDay } from "./time.ts";
import type { Activity, Gap, Profile } from "./types.ts";

export type Allowed = { activity: Activity; durationMin: number };

const hm = (t: string) => t.slice(0, 5);
const clock = (minutes: number) => `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;

export function rhythmSummary(p: Profile): string {
  return `Wakes ${hm(p.wake)}, bedtime ${hm(p.bedtime)}. Breakfast ${hm(p.breakfast)}, lunch ${hm(p.lunch)}, dinner ${hm(p.dinner)}. ` +
    `Quiet hours ${hm(p.quiet_start)}-${hm(p.quiet_end)} (no suggestions).`;
}

const energyText = (e: Gap["energy"]) => e === null ? "not given" : `${e} of 3 (1 = low, 3 = high)`;

/** Source A: a new suggestion tailored to this person, built from their activities and history. */
export function buildPromptA(profile: Profile, gap: Gap, activities: Activity[], historyLines: string[]): string {
  const minute = localMinuteOfDay(gap.start, profile.timezone);
  const statement = clean(profile.wellness_statement, 200);
  const rows = activities.map((a) =>
    `- ${a.id} | ${clean(a.name)} | ${clean(a.category)} | ${a.duration_min} min | ${a.location} | priority ${a.priority} | ` +
    (a.weekly_intention === null ? "whenever" : `about ${a.weekly_intention} times a week`)
  );
  return [
    "You suggest one wellness activity for a free gap in one person's day, tailored to them.",
    "Base it on their own activities and history below. It can be one of their activities as is, a shorter or adapted",
    "version of one, or a new idea in the same spirit. It must fit inside the gap.",
    "",
    "Guidance:",
    "- Prefer the kinds of activities this person completes and rates as a good fit in similar time-of-day and gap-length slots (see History).",
    "- Favor higher priorities (3 = most important) and activities that are behind their weekly intention.",
    "- Steer away from what they recently skipped or rated poorly, and from the reasons they gave.",
    "- Avoid repeating the most recent activity.",
    "- Occasionally choose something that has not been suggested recently.",
    "- Respect where each activity can be done (indoors, outdoors, anywhere).",
    "- Title: 2 to 5 words. Description: one short sentence saying what to do. Reason: one short sentence on why it suits them.",
    "",
    `Gap: ${gap.minutes} minutes, starting ${clock(minute)} on ${localWeekday(gap.start, profile.timezone)} (${timeOfDay(minute)}). ` +
    `Energy: ${energyText(gap.energy)}.`,
    `Daily rhythm: ${rhythmSummary(profile)}`,
    ...(statement ? [`What wellness means to them: "${statement}"`] : []),
    "",
    "Their activities (id | name | category | usual minutes | where | priority | weekly intention):",
    ...rows,
    "",
    "History:",
    ...historyLines.map((l) => `- ${l}`),
    "",
    'Reply with JSON only: {"title": "<2-5 words>", "description": "<one short sentence>", ' +
    `"duration_min": <whole number of minutes, at most ${gap.minutes}>, ` +
    '"based_on": "<id of the activity it builds on, or null>", "reason": "<one short sentence>"}',
  ].join("\n");
}

export function buildPromptB(gap: Gap): string {
  const energy = gap.energy === null ? "" : ` and energy level ${gap.energy} (1 = low, 3 = high)`;
  return [
    `I have ${gap.minutes} minutes${energy}. What should I do for my wellness?`,
    "",
    'Reply with JSON only: {"title": "<2-5 words>", "description": "<one short sentence>", "duration_min": <whole number of minutes, at most ' +
    `${gap.minutes}>}`,
  ].join("\n");
}

/** Parse model text as a JSON object, tolerating code fences or stray words around it. */
export function parseJsonObject(text: string): Record<string, unknown> {
  const t = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  for (const candidate of [t, t.slice(t.indexOf("{"), t.lastIndexOf("}") + 1)]) {
    try {
      const v = JSON.parse(candidate);
      if (v && typeof v === "object" && !Array.isArray(v)) return v as Record<string, unknown>;
    } catch { /* try the next form */ }
  }
  throw new Error("invalid_output: not a JSON object");
}

const str = (v: unknown) => (typeof v === "string" ? v : "");

/** Shared by A and B: valid fields, fits the gap, and passes the same hard filters as everything else. */
function parseCard(o: Record<string, unknown>, gap: Gap, profile: Profile) {
  const title = clean(str(o.title), 50);
  const description = clean(str(o.description), 160);
  const durationMin = o.duration_min;
  if (!title || !description) throw new Error("invalid_output: missing title or description");
  if (typeof durationMin !== "number" || !Number.isInteger(durationMin) || durationMin < 1) {
    throw new Error("invalid_output: duration_min is not a whole number");
  }
  const verdict = checkCandidate({ durationMin, text: `${title} ${description}` }, gap, profile);
  if (!verdict.ok) throw new Error(`filtered: ${verdict.reason}`);
  return { title, description, durationMin };
}

/** Source A. `based_on` must be one of their activities (otherwise it is dropped); a high-intensity
 *  base activity is also checked against the meal window. */
export function parseA(text: string, gap: Gap, profile: Profile, activities: Activity[]) {
  const o = parseJsonObject(text);
  const card = parseCard(o, gap, profile);
  const basedOn = activities.find((a) => a.id === o.based_on) ?? null;
  if (basedOn) {
    const verdict = checkCandidate({ durationMin: card.durationMin, category: basedOn.category }, gap, profile);
    if (!verdict.ok) throw new Error(`filtered: ${verdict.reason}`);
  }
  return { ...card, basedOn, reason: clean(str(o.reason), 160) || null };
}

/** Source B. */
export function parseB(text: string, gap: Gap, profile: Profile) {
  return parseCard(parseJsonObject(text), gap, profile);
}
