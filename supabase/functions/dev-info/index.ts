// POST /functions/v1/dev-info   (no body)
// For the hidden developer screen: the caller's history summary as it would be built right now, and the
// last Source A prompt they were sent. It never says which card came from which source.
import { adminClient, authenticate, json } from "../_shared/auth.ts";
import { loadContext } from "../_shared/load.ts";
import { buildHistorySummary } from "../_shared/history.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const db = adminClient();
  const uid = await authenticate(req, db);
  if (!uid) return json({ error: "unauthorized" }, 401);

  let context;
  try {
    context = await loadContext(db, uid);
  } catch {
    return json({ error: "load_failed" }, 500);
  }
  const { profile, activities, events, shown, sets } = context;

  const historyNow = buildHistorySummary({
    activities, events, shown, now: new Date(), timezone: profile.timezone ?? "UTC",
  });

  // Look back over the few most recent sets for the latest Source A prompt.
  let last = null;
  const recent = sets.slice(0, 5);
  if (recent.length > 0) {
    const { data, error } = await db.from("suggestions")
      .select("set_id, sources, prompt_snapshot, model, error")
      .in("set_id", recent.map((s) => s.id))
      .or("sources.cs.{A},sources.cs.{A_fallback}");
    if (error) {
      console.error("dev-info: load prompts failed", error.message);
      return json({ error: "load_failed" }, 500);
    }
    for (const set of recent) {
      const a = (data ?? []).find((r) => r.set_id === set.id);
      if (!a) continue;
      const used = await db.from("suggestion_sets").select("history_summary").eq("id", set.id).single();
      last = {
        set_created_at: set.created_at,
        status: (a.sources as string[]).includes("A_fallback") ? "fallback" : "model",
        error: a.error,
        model: a.model,
        prompt: a.prompt_snapshot,
        history_summary_used: used.data?.history_summary ?? null,
      };
      break;
    }
  }
  return json({ history_summary_now: historyNow, last });
});
