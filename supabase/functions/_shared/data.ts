// Turns database rows into the history inputs. Kept separate from the HTTP handler so it can be tested.
import type { HistoryEvent, ShownRecord } from "./types.ts";

export interface OutcomeRow {
  set_id: string;
  chosen_suggestion_id: string | null;
  none_reason: string | null;
  completed: boolean | null;
  skip_reason: string | null;
  fit_rating?: number | null;
  ts: string;
}
export interface SetRow {
  id: string;
  created_at: string;
  gap: { start_time: string; minutes: number } | null;
}
export interface SuggestionRow {
  id: string;
  set_id: string;
  activity_id: string | null;
  title: string;
}

export function assembleHistory(outcomes: OutcomeRow[], sets: SetRow[], suggestions: SuggestionRow[]) {
  const setById = new Map(sets.map((s) => [s.id, s]));
  const sugById = new Map(suggestions.map((s) => [s.id, s]));

  const events: HistoryEvent[] = [];
  for (const o of outcomes) {
    const set = setById.get(o.set_id);
    if (!set?.gap) continue;
    const chosen = o.chosen_suggestion_id ? sugById.get(o.chosen_suggestion_id) : undefined;
    events.push({
      ts: o.ts,
      gapStart: set.gap.start_time,
      gapMinutes: set.gap.minutes,
      isNone: o.chosen_suggestion_id === null,
      noneReason: o.none_reason,
      chosenActivityId: chosen?.activity_id ?? null,
      chosenTitle: chosen?.title ?? null,
      completed: o.completed,
      skipReason: o.skip_reason,
      fitRating: o.fit_rating ?? null,
    });
  }

  const shown: ShownRecord[] = [];
  for (const s of suggestions) {
    const set = setById.get(s.set_id);
    if (set && s.activity_id) shown.push({ ts: set.created_at, activityId: s.activity_id });
  }
  return { events, shown };
}
