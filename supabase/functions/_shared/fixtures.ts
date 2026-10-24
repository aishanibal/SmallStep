// Seeded data shared by the tests.
import type { Activity, Gap, HistoryEvent, Profile } from "./types.ts";

export const profile: Profile = {
  wake: "07:00", bedtime: "23:00", breakfast: "08:00", lunch: "12:30", dinner: "19:00",
  quiet_start: "22:00", quiet_end: "07:00", timezone: "America/New_York", wellness_statement: null,
};

export const walk: Activity = { id: "walk", name: "Morning walk", category: "movement", duration_min: 20, location: "outdoors", priority: 3, weekly_intention: 4 };
export const stretch: Activity = { id: "stretch", name: "Gentle stretch", category: "yoga", duration_min: 10, location: "anywhere", priority: 2, weekly_intention: 3 };
export const breathe: Activity = { id: "breathe", name: "Breathing pause", category: "mindfulness", duration_min: 5, location: "anywhere", priority: 2, weekly_intention: null };
export const circuit: Activity = { id: "circuit", name: "Strength circuit", category: "strength", duration_min: 15, location: "indoors", priority: 1, weekly_intention: 2 };
export const activities = [walk, stretch, breathe, circuit];

/** A local New York time on 2026-03-10 (EDT after 8 Mar, so UTC-4) as a Date. */
export const ny = (hhmm: string): Date => new Date(`2026-03-10T${hhmm}:00-04:00`);
export const gapAt = (hhmm: string, minutes: number): Gap => ({ start: ny(hhmm), minutes, energy: null });

export const NOW = new Date("2026-03-10T16:00:00Z"); // 12:00 in New York

let n = 0;
export function event(p: Partial<HistoryEvent> & { daysAgo: number; gapLocal: string }): HistoryEvent {
  const ts = new Date(NOW.getTime() - p.daysAgo * 86400000).toISOString();
  const day = ts.slice(0, 10);
  n += 1;
  return {
    ts,
    gapStart: new Date(`${day}T${p.gapLocal}:00-04:00`).toISOString(),
    gapMinutes: 20,
    isNone: false,
    noneReason: null,
    chosenActivityId: null,
    chosenTitle: null,
    completed: null,
    skipReason: null,
    fitRating: null,
    ...p,
  };
}
