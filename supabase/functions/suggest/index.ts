// POST /functions/v1/suggest   body: {"gap_id": "<uuid>"}
// Authenticates the caller, reads their profile / activities / history, builds three cards from three
// hidden sources, saves the set, and returns the shuffled cards without revealing sources.
import { adminClient, authenticate, json } from "../_shared/auth.ts";
import { geminiCaller } from "../_shared/gemini.ts";
import { isSetupComplete, loadContext } from "../_shared/load.ts";
import { generateCards, toPublicCard } from "../_shared/suggest_core.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const db = adminClient();
  const uid = await authenticate(req, db);
  if (!uid) return json({ error: "unauthorized" }, 401);

  let gapId: unknown;
  try {
    gapId = (await req.json()).gap_id;
  } catch { /* handled below */ }
  if (typeof gapId !== "string" || !UUID.test(gapId)) return json({ error: "gap_id_required" }, 400);

  let context, gapQ;
  try {
    [context, gapQ] = await Promise.all([
      loadContext(db, uid),
      db.from("gaps").select("*").eq("id", gapId).eq("participant_id", uid).maybeSingle(),
    ]);
  } catch {
    return json({ error: "load_failed" }, 500);
  }
  if (gapQ.error) {
    console.error("suggest: load gap failed", gapQ.error.message);
    return json({ error: "load_failed" }, 500);
  }
  if (!gapQ.data) return json({ error: "gap_not_found" }, 404);
  const { profile, activities, events, shown } = context;
  if (!isSetupComplete(profile, activities)) return json({ error: "setup_incomplete" }, 409);

  const model = Deno.env.get("GEMINI_MODEL") ?? null;
  const { cards, historySummary } = await generateCards(
    {
      profile, activities, events, shown, now: new Date(),
      gap: { start: new Date(gapQ.data.start_time), minutes: gapQ.data.minutes, energy: gapQ.data.energy },
    },
    { callModel: geminiCaller(Deno.env.get("GEMINI_API_KEY"), model ?? undefined), modelName: model, rng: Math.random },
  );

  // Nothing fits (for example the gap is inside quiet hours): no set, the app shows a gentle message.
  if (cards.length === 0) return json({ set_id: null, cards: [] });

  const setId = crypto.randomUUID();
  const { error: setError } = await db.from("suggestion_sets").insert({
    id: setId, participant_id: uid, gap_id: gapId, history_summary: historySummary.join("\n"),
  });
  if (setError) {
    console.error("suggest: save set failed", setError.message);
    return json({ error: "save_failed" }, 500);
  }
  const rows = cards.map((c) => ({
    id: crypto.randomUUID(), set_id: setId, sources: c.sources, activity_id: c.activityId, title: c.title,
    description: c.description, duration_min: c.durationMin, position: c.position, reason_text: c.reasonText,
    prompt_snapshot: c.promptSnapshot, model: c.model, latency_ms: c.latencyMs, error: c.error,
  }));
  const { error: sugError } = await db.from("suggestions").insert(rows);
  if (sugError) {
    console.error("suggest: save suggestions failed", sugError.message);
    await db.from("suggestion_sets").delete().eq("id", setId);
    return json({ error: "save_failed" }, 500);
  }

  return json({ set_id: setId, cards: cards.map((c, i) => toPublicCard(c, rows[i].id)) });
});
