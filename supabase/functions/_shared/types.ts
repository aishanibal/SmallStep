// Shapes shared by the Edge Functions. Times of day are "HH:MM" or "HH:MM:SS" (Postgres `time`).

export interface Profile {
  wake: string;
  bedtime: string;
  breakfast: string;
  lunch: string;
  dinner: string;
  quiet_start: string;
  quiet_end: string;
  timezone: string; // IANA name
  wellness_statement: string | null;
}

export interface Activity {
  id: string;
  name: string;
  category: string;
  duration_min: number;
  location: "indoors" | "outdoors" | "anywhere";
  priority: 1 | 2 | 3;
  weekly_intention: number | null; // null = "whenever"
}

export interface Gap {
  start: Date;
  minutes: number;
  energy: 1 | 2 | 3 | null;
}

/** One logged outcome (a chosen card, or "None of these"), joined with its gap. */
export interface HistoryEvent {
  ts: string; // outcome timestamp, ISO UTC
  gapStart: string; // ISO UTC
  gapMinutes: number;
  isNone: boolean;
  noneReason: string | null;
  chosenActivityId: string | null; // null for "none" and for Source B picks
  chosenTitle: string | null; // card title (used when there is no activity id)
  completed: boolean | null; // null = chosen but not resolved yet
  skipReason: string | null;
  fitRating: number | null; // 1-5, null if not rated
}

/** A card that was shown for one of the participant's activities (Source A or C), resolved or not. */
export interface ShownRecord {
  ts: string; // suggestion set created_at, ISO UTC
  activityId: string;
}
