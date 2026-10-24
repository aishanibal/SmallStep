// Loads one participant's profile, activities and history for the Edge Functions (service role).
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.49.4";
import { assembleHistory, type SetRow } from "./data.ts";
import type { Activity, HistoryEvent, Profile, ShownRecord } from "./types.ts";

export interface ParticipantContext {
  profile: Profile;
  activities: Activity[];
  events: HistoryEvent[];
  shown: ShownRecord[];
  /** Most recent first. */
  sets: SetRow[];
}

const PROFILE_FIELDS = ["wake", "bedtime", "breakfast", "lunch", "dinner", "quiet_start", "quiet_end", "timezone"] as const;

export const isSetupComplete = (profile: Profile, activities: Activity[]) =>
  activities.length > 0 && PROFILE_FIELDS.every((f) => Boolean(profile[f]));

/** Throws Error("load_failed") after logging the cause; the caller turns that into a 500. */
export async function loadContext(db: SupabaseClient, uid: string): Promise<ParticipantContext> {
  const [profileQ, activitiesQ, outcomesQ, setsQ] = await Promise.all([
    db.from("profiles").select("*").eq("id", uid).single(),
    db.from("activities").select("*").eq("participant_id", uid),
    db.from("outcomes").select("set_id, chosen_suggestion_id, none_reason, completed, skip_reason, fit_rating, ts")
      .eq("participant_id", uid).order("ts", { ascending: false }).limit(100),
    db.from("suggestion_sets").select("id, created_at, gap:gaps(start_time, minutes)")
      .eq("participant_id", uid).order("created_at", { ascending: false }).limit(100),
  ]);
  const failed = [profileQ, activitiesQ, outcomesQ, setsQ].find((q) => q.error);
  if (failed?.error) {
    console.error("load failed:", failed.error.message);
    throw new Error("load_failed");
  }
  const sets = setsQ.data as unknown as SetRow[];
  let suggestions: unknown[] = [];
  if (sets.length > 0) {
    const sugQ = await db.from("suggestions").select("id, set_id, activity_id, title").in("set_id", sets.map((s) => s.id));
    if (sugQ.error) {
      console.error("load suggestions failed:", sugQ.error.message);
      throw new Error("load_failed");
    }
    suggestions = sugQ.data;
  }
  const { events, shown } = assembleHistory(outcomesQ.data as never, sets, suggestions as never);
  return { profile: profileQ.data as Profile, activities: activitiesQ.data as Activity[], events, shown, sets };
}
