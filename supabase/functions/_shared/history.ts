// History summary: turns a participant's logged outcomes into 3-8 short lines for Source A's prompt.
// The model does not learn; adaptation comes from this text changing as outcomes are logged.
import {
  GAP_BUCKET_LABEL,
  GAP_BUCKET_ORDER,
  gapBucket,
  type GapBucket,
  localMinuteOfDay,
  TIME_OF_DAY_ORDER,
  timeOfDay,
  type TimeOfDay,
} from "./time.ts";
import type { Activity, HistoryEvent, ShownRecord } from "./types.ts";

export const HISTORY_CONFIG = {
  maxLineChars: 200, // hard cap per line, so the whole summary stays under 8 x 200 characters
  maxItemsPerLine: 3,
  recentSkipDays: 14,
  notSuggestedDays: 3, // an activity not shown for this many days counts as "not suggested recently"
  intentionWindowDays: 7,
  lastEventCount: 5,
};

export interface HistoryInput {
  activities: Activity[];
  events: HistoryEvent[];
  shown: ShownRecord[];
  now: Date;
  timezone: string;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** Free text goes into a prompt: one line, no odd characters, bounded length. */
export function clean(s: string | null | undefined, max = 30): string {
  const t = (s ?? "").replace(/[\r\n\t]+/g, " ").replace(/[^\p{L}\p{N} .,'&()\-_/]/gu, "").replace(/\s+/g, " ").trim();
  return t.length > max ? t.slice(0, max - 1) + "…" : t;
}

const words = (reason: string) => clean(reason, 24).replace(/_/g, " ");

function truncate(line: string): string {
  const max = HISTORY_CONFIG.maxLineChars;
  return line.length > max ? line.slice(0, max - 1) + "…" : line;
}

/** "Prefix: a; b; c." Drops whole items from the end until it fits, rather than cutting one in half. */
function listLine(prefix: string, items: string[]): string {
  for (let n = items.length; n > 1; n--) {
    const s = `${prefix} ${items.slice(0, n).join("; ")}.`;
    if (s.length <= HISTORY_CONFIG.maxLineChars) return s;
  }
  return truncate(`${prefix} ${items[0]}.`);
}

/** Completed picks per activity within the last `days` days. */
export function doneInWindow(events: HistoryEvent[], now: Date, days: number): Map<string, number> {
  const out = new Map<string, number>();
  for (const e of events) {
    if (e.completed !== true || !e.chosenActivityId) continue;
    if (now.getTime() - new Date(e.ts).getTime() > days * DAY_MS) continue;
    out.set(e.chosenActivityId, (out.get(e.chosenActivityId) ?? 0) + 1);
  }
  return out;
}

/** Most recent time each activity was shown on a card (ms since epoch). */
export function lastShownMap(shown: ShownRecord[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const s of shown) {
    const t = new Date(s.ts).getTime();
    if (t > (out.get(s.activityId) ?? -Infinity)) out.set(s.activityId, t);
  }
  return out;
}

type Tally = { done: number; total: number };
const bump = (t: Tally, completed: boolean) => {
  t.total += 1;
  if (completed) t.done += 1;
};

/** "morning 3/4, evening 0/2" for the buckets that have data, in a fixed order. */
function bucketParts<K extends string>(order: K[], tallies: Map<K, Tally>, label: (k: K) => string): string {
  return order.filter((k) => tallies.has(k)).map((k) => `${label(k)} ${tallies.get(k)!.done}/${tallies.get(k)!.total}`).join(", ");
}

export function buildHistorySummary(input: HistoryInput): string[] {
  const { activities, events, shown, now, timezone } = input;
  const cfg = HISTORY_CONFIG;
  const nameOf = new Map(activities.map((a) => [a.id, clean(a.name)]));
  const nowMs = now.getTime();
  const lines: string[] = [];

  // Resolved picks of the participant's own activities, bucketed by slot.
  const byTod = new Map<string, Map<TimeOfDay, Tally>>();
  const byGap = new Map<string, Map<GapBucket, Tally>>();
  const resolvedCount = new Map<string, number>();
  for (const e of events) {
    if (!e.chosenActivityId || e.completed === null || !nameOf.has(e.chosenActivityId)) continue;
    const id = e.chosenActivityId;
    const tod = timeOfDay(localMinuteOfDay(new Date(e.gapStart), timezone));
    const gb = gapBucket(e.gapMinutes);
    if (!byTod.has(id)) byTod.set(id, new Map());
    if (!byGap.has(id)) byGap.set(id, new Map());
    const t1 = byTod.get(id)!, t2 = byGap.get(id)!;
    if (!t1.has(tod)) t1.set(tod, { done: 0, total: 0 });
    if (!t2.has(gb)) t2.set(gb, { done: 0, total: 0 });
    bump(t1.get(tod)!, e.completed);
    bump(t2.get(gb)!, e.completed);
    resolvedCount.set(id, (resolvedCount.get(id) ?? 0) + 1);
  }
  const byMostData = (ids: Iterable<string>) =>
    [...ids].sort((a, b) => (resolvedCount.get(b)! - resolvedCount.get(a)!) || nameOf.get(a)!.localeCompare(nameOf.get(b)!))
      .slice(0, cfg.maxItemsPerLine);

  if (byTod.size > 0) {
    const items = byMostData(byTod.keys()).map((id) =>
      `${nameOf.get(id)} ${bucketParts(TIME_OF_DAY_ORDER, byTod.get(id)!, (k) => k)}`
    );
    lines.push(listLine("Done/tried by time of day:", items));
    const gapItems = byMostData(byGap.keys()).map((id) =>
      `${nameOf.get(id)} ${bucketParts(GAP_BUCKET_ORDER, byGap.get(id)!, (k) => GAP_BUCKET_LABEL[k])}`
    );
    lines.push(listLine("Done/tried by gap length:", gapItems));
  }

  // Recent skip reasons per activity.
  const skips = new Map<string, Map<string, number>>();
  for (const e of events) {
    if (e.completed !== false || !e.chosenActivityId || !nameOf.has(e.chosenActivityId)) continue;
    if (nowMs - new Date(e.ts).getTime() > cfg.recentSkipDays * DAY_MS) continue;
    const reasons = skips.get(e.chosenActivityId) ?? new Map<string, number>();
    const r = e.skipReason ? words(e.skipReason) : "no reason given";
    reasons.set(r, (reasons.get(r) ?? 0) + 1);
    skips.set(e.chosenActivityId, reasons);
  }
  if (skips.size > 0) {
    const total = (m: Map<string, number>) => [...m.values()].reduce((a, b) => a + b, 0);
    const items = [...skips.entries()].sort((a, b) => total(b[1]) - total(a[1])).slice(0, cfg.maxItemsPerLine).map(([id, m]) =>
      `${nameOf.get(id)} - ` + [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, 2).map(([r, n]) => n > 1 ? `${r} x${n}` : r).join(", ")
    );
    lines.push(listLine(`Skipped in the last ${cfg.recentSkipDays} days:`, items));
  }

  // Average fit rating per activity (1-5).
  const fits = new Map<string, number[]>();
  for (const e of events) {
    if (!e.fitRating || !e.chosenActivityId || !nameOf.has(e.chosenActivityId)) continue;
    fits.set(e.chosenActivityId, [...(fits.get(e.chosenActivityId) ?? []), e.fitRating]);
  }
  if (fits.size > 0) {
    const avg = (r: number[]) => r.reduce((a, b) => a + b, 0) / r.length;
    const items = [...fits.entries()].sort((a, b) => b[1].length - a[1].length || avg(b[1]) - avg(a[1]))
      .map(([id, r]) => `${nameOf.get(id)} ${avg(r).toFixed(1)} (${r.length} rated)`);
    lines.push(listLine("Fit ratings, 1-5 average:", items));
  }

  // Why they turned down whole sets recently.
  const nones = new Map<string, number>();
  for (const e of events) {
    if (!e.isNone || nowMs - new Date(e.ts).getTime() > cfg.recentSkipDays * DAY_MS) continue;
    const r = e.noneReason === "wanted_another" ? "asked for different ideas" : (e.noneReason ? words(e.noneReason) : "no reason given");
    nones.set(r, (nones.get(r) ?? 0) + 1);
  }
  if (nones.size > 0) {
    const items = [...nones.entries()].sort((a, b) => b[1] - a[1]).map(([r, n]) => n > 1 ? `${r} x${n}` : r);
    lines.push(listLine(`Chose "none of these" in the last ${cfg.recentSkipDays} days:`, items));
  }

  // Activities not suggested recently (always present).
  const lastShown = lastShownMap(shown);
  const stale = activities
    .map((a) => ({ name: nameOf.get(a.id)!, days: lastShown.has(a.id) ? Math.floor((nowMs - lastShown.get(a.id)!) / DAY_MS) : Infinity }))
    .filter((x) => x.days >= cfg.notSuggestedDays)
    .sort((a, b) => (b.days - a.days) || a.name.localeCompare(b.name))
    .slice(0, cfg.maxItemsPerLine);
  lines.push(
    stale.length === 0
      ? `Every activity was suggested in the last ${cfg.notSuggestedDays} days.`
      : listLine("Not suggested recently:", stale.map((x) => x.days === Infinity ? `${x.name} (never)` : `${x.name} (${x.days}d ago)`)),
  );

  // Weekly intention, last 7 days (always present).
  const doneThisWeek = doneInWindow(events, now, cfg.intentionWindowDays);
  const withIntention = activities
    .filter((a) => a.weekly_intention !== null)
    .map((a) => ({ name: nameOf.get(a.id)!, done: doneThisWeek.get(a.id) ?? 0, goal: a.weekly_intention! }))
    .sort((a, b) => (b.goal - b.done) - (a.goal - a.done) || a.name.localeCompare(b.name))
    .slice(0, cfg.maxItemsPerLine + 1);
  lines.push(
    withIntention.length === 0
      ? "No weekly intentions set."
      : listLine(`This week (${cfg.intentionWindowDays}d) vs intention:`, withIntention.map((x) => `${x.name} ${x.done}/${x.goal} ${x.done < x.goal ? "behind" : "met"}`)),
  );

  // Last 5 events, newest first (always present).
  const recent = [...events].sort((a, b) => new Date(b.ts).getTime() - new Date(a.ts).getTime()).slice(0, cfg.lastEventCount);
  const label = (e: HistoryEvent) => {
    if (e.isNone) {
      if (e.noneReason === "wanted_another") return "asked for different ideas";
      return e.noneReason ? `none of these (${words(e.noneReason)})` : "none of these";
    }
    const name = e.chosenActivityId ? (nameOf.get(e.chosenActivityId) ?? "a removed activity") : clean(e.chosenTitle) || "an idea";
    const fit = e.fitRating ? `, fit ${e.fitRating}/5` : "";
    if (e.completed === true) return `${name} done${fit}`;
    if (e.completed === false) return e.skipReason ? `${name} skipped (${words(e.skipReason)}${fit})` : `${name} skipped${fit}`;
    return `${name} chosen, not finished`;
  };
  lines.push(recent.length === 0 ? "Last events: none yet." : listLine("Last events, newest first:", recent.map(label)));

  return lines.map(truncate);
}
