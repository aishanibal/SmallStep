import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.13";
import { generateCards, GENERIC_IDEAS, ruleBasedPick, toPublicCard, type Card, type Deps, type SuggestInput } from "./suggest_core.ts";
import { activities, breathe, circuit, event, gapAt, NOW, profile, stretch, walk } from "./fixtures.ts";
import type { ModelCaller } from "./gemini.ts";

const input = (over: Partial<SuggestInput> = {}): SuggestInput => ({
  profile: { ...profile, wellness_statement: "Feeling steady and unhurried." },
  activities, gap: { ...gapAt("14:00", 20), energy: 2 }, events: [], shown: [], now: NOW, ...over,
});

const isA = (prompt: string) => prompt.startsWith("You suggest one wellness activity");
const modelReturning = (a: unknown, b: unknown): { call: ModelCaller; prompts: string[] } => {
  const prompts: string[] = [];
  return {
    prompts,
    call: (prompt) => {
      prompts.push(prompt);
      const out = isA(prompt) ? a : b;
      if (out instanceof Error) return Promise.reject(out);
      return Promise.resolve({ text: typeof out === "string" ? out : JSON.stringify(out), latencyMs: 123 });
    },
  };
};
const goodA = { title: "Desk stretch break", description: "Stand up and stretch your back and arms.", duration_min: 10, based_on: "stretch", reason: "You finish stretches in the afternoon." };
const goodB = { title: "Slow breathing", description: "Breathe in for four, out for six.", duration_min: 5 };
const deps = (call: ModelCaller, rng: () => number = () => 0): Deps => ({ callModel: call, modelName: "test-model", rng });
const sourcesOf = (cards: Card[]) => cards.map((c) => c.sources.join("+")).sort();
const cardA = (cards: Card[]) => cards.find((c) => c.sources[0] === "A" || c.sources[0] === "A_fallback")!;

Deno.test("happy path: three cards, one per source; A is written by the model for this person", async () => {
  const { cards } = await generateCards(input(), deps(modelReturning(goodA, goodB).call)); // rng 0 -> C picks walk
  assertEquals(sourcesOf(cards), ["A", "B", "C"]);
  assertEquals(cards.map((c) => c.position).sort(), [0, 1, 2]);
  const a = cardA(cards);
  assertEquals([a.title, a.description, a.durationMin, a.activityId], ["Desk stretch break", "Stand up and stretch your back and arms.", 10, "stretch"]);
  assertEquals([a.reasonText, a.model, a.latencyMs, a.error], ["You finish stretches in the afternoon.", "test-model", 123, null]);
  assertEquals(cards.find((c) => c.sources[0] === "C")!.activityId, "walk");
});

Deno.test("A may propose something new that isn't on their list", async () => {
  const fresh = { ...goodA, title: "Window light break", description: "Step to a window and look far away.", duration_min: 5, based_on: null };
  const a = cardA((await generateCards(input(), deps(modelReturning(fresh, goodB).call))).cards);
  assertEquals([a.sources[0], a.activityId, a.title], ["A", null, "Window light break"]);
  // a based_on that isn't one of theirs is dropped, not fatal
  const stray = cardA((await generateCards(input(), deps(modelReturning({ ...goodA, based_on: "someone-else" }, goodB).call))).cards);
  assertEquals([stray.sources[0], stray.activityId], ["A", null]);
});

Deno.test("A still works when none of their activities fits the gap as is", async () => {
  // a 6-minute gap: walk 20, stretch 10, circuit 15 are too long; breathing (5) fits but say the model adapts the stretch
  const short = { ...goodA, title: "Two-minute stretch", duration_min: 2 };
  const { cards } = await generateCards(input({ gap: gapAt("14:00", 6), activities: [walk, stretch, circuit] }), deps(modelReturning(short, goodB).call));
  assertEquals(cardA(cards).title, "Two-minute stretch");
  const c = cards.find((x) => x.sources[0] === "C")!;
  assert(c && c.durationMin <= 6, "C offers a shortened version that fits");
  assertEquals(cards.length, 3);
});

Deno.test("same model, one call each for A and B", async () => {
  const m = modelReturning(goodA, goodB);
  await generateCards(input(), deps(m.call));
  assertEquals(m.prompts.length, 2);
});

Deno.test("C avoids A's activity and a copied title still leaves three cards", async () => {
  const exact = { ...goodA, title: "Morning walk", duration_min: 20, based_on: "walk" };
  const r = await generateCards(input(), deps(modelReturning(exact, goodB).call));  // rng 0 would have picked walk
  assertEquals(sourcesOf(r.cards), ["A", "B", "C"]);
  assert(r.cards.find((x) => x.sources[0] === "C")!.activityId !== "walk");
  const only = await generateCards(input({ activities: [walk] }), deps(modelReturning(exact, goodB).call));
  assertEquals(sourcesOf(only.cards), ["A", "B", "C"]);
  assertEquals(only.cards.length, 3);
  const variation = { ...goodA, title: "Walk to the corner", duration_min: 15, based_on: "walk" };
  assertEquals(sourcesOf((await generateCards(input(), deps(modelReturning(variation, goodB).call))).cards), ["A", "B", "C"]);
});

Deno.test("order is randomised and all orders are reachable", async () => {
  const m = modelReturning(goodA, goodB);
  const seen = new Set<string>();
  let seed = 7;
  const rng = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  for (let i = 0; i < 60; i++) {
    const { cards } = await generateCards(input(), deps(m.call, rng));
    if (cards.length === 3) seen.add([...cards].sort((x, y) => x.position - y.position).map((c) => c.sources[0]).join(""));
  }
  assertEquals(seen.size, 6);
});

Deno.test("what the app receives has no source, reason, prompt, model or error", async () => {
  const { cards } = await generateCards(input(), deps(modelReturning(goodA, goodB).call));
  for (const c of cards) {
    assertEquals(Object.keys(toPublicCard(c, "id1")).sort(), ["description", "duration_min", "id", "position", "title"]);
  }
});

Deno.test("A falls back to a rule-based pick (A_fallback, error logged) on bad or rule-breaking output", async () => {
  const cases: [unknown, string][] = [
    ["sorry, I cannot help", "invalid_output"],
    [{ ...goodA, title: "" }, "invalid_output"],
    [{ ...goodA, duration_min: 45 }, "too_long"],
    [{ ...goodA, duration_min: "ten" }, "invalid_output"],
    [new Error("gemini http 503"), "503"],
  ];
  for (const [out, expected] of cases) {
    const { cards } = await generateCards(input(), deps(modelReturning(out, goodB).call));
    const a = cardA(cards);
    assertEquals(a.sources[0], "A_fallback", JSON.stringify(out));
    assertStringIncludes(a.error!, expected);
    assert(cards.some((c) => c.sources.includes("B")), "B still shown");
  }
});

Deno.test("A's output goes through the same hard filters (meal window by text and by its base activity)", async () => {
  const jog = { ...goodA, title: "Quick jog", description: "Go for a run around the block.", based_on: null };
  const r1 = await generateCards(input({ gap: gapAt("12:40", 30) }), deps(modelReturning(jog, goodB).call));
  assertStringIncludes(cardA(r1.cards).error!, "filtered: after_meal");
  const fromCircuit = { ...goodA, title: "Mini circuit", description: "A few slow squats.", based_on: "circuit" };
  const r2 = await generateCards(input({ gap: gapAt("12:40", 30) }), deps(modelReturning(fromCircuit, goodB).call));
  assertStringIncludes(cardA(r2.cards).error!, "filtered: after_meal");
});

Deno.test("model not configured: A falls back, B shows a generic idea, nothing throws", async () => {
  const failing: ModelCaller = () => Promise.reject(new Error("GEMINI_API_KEY is not set"));
  const { cards } = await generateCards(input(), deps(failing));
  assertEquals(cardA(cards).sources[0], "A_fallback");
  const b = cards.find((c) => c.sources[0] === "B")!;
  assertStringIncludes(b.error!, "GEMINI_API_KEY");
  assert(GENERIC_IDEAS.some((i) => i.title === b.title));
});

Deno.test("B: invalid output or a rule break is replaced by a generic idea that follows the rules", async () => {
  const jog = { title: "Quick jog", description: "Go for a run around the block.", duration_min: 15 };
  const { cards } = await generateCards(input({ gap: gapAt("12:40", 30) }), deps(modelReturning(goodA, jog).call));
  const b = cards.find((c) => c.sources[0] === "B")!;
  assertStringIncludes(b.error!, "filtered: after_meal");
  assert(GENERIC_IDEAS.some((i) => i.title === b.title));
  const r = await generateCards(input(), deps(modelReturning(goodA, { ...goodB, duration_min: 45 }).call));
  assertStringIncludes(r.cards.find((c) => c.sources[0] === "B")!.error!, "too_long");
});

Deno.test("hard filters apply to every source", async () => {
  // 21:50, 30 minutes: quiet hours begin at 22:00, so only items of 10 minutes or less fit.
  const m = modelReturning({ ...goodA, duration_min: 10 }, { ...goodB, duration_min: 10 });
  const { cards } = await generateCards(input({ gap: gapAt("21:50", 30) }), deps(m.call));
  for (const c of cards) assert(c.durationMin <= 10, `${c.title} ${c.durationMin}`);
  assert(cards.length > 0);
});

Deno.test("nothing fits: no cards (a gap that starts in quiet hours)", async () => {
  const { cards } = await generateCards(input({ gap: gapAt("23:30", 30) }), deps(modelReturning(goodA, goodB).call));
  assertEquals(cards, []);
});

Deno.test("Source A's prompt carries all the context", async () => {
  const m = modelReturning(goodA, goodB);
  const events = [
    event({ daysAgo: 1, gapLocal: "10:00", chosenActivityId: "walk", completed: true, fitRating: 4 }),
    event({ daysAgo: 2, gapLocal: "18:00", chosenActivityId: "circuit", completed: false, skipReason: "no_energy", fitRating: 2 }),
    event({ daysAgo: 0.5, gapLocal: "11:00", isNone: true, noneReason: "wrong_length" }),
  ];
  await generateCards(input({ events }), deps(m.call));
  const prompt = m.prompts.find(isA)!;
  for (const s of ["20 minutes", "14:00", "Tuesday", "afternoon", "Energy: 2 of 3", "Morning walk", "Gentle stretch", "Strength circuit",
    "Breathing pause", "priority 3", "about 4 times a week", "whenever", "Wakes 07:00", "Quiet hours 22:00-07:00",
    "Feeling steady and unhurried", "History:", "Done/tried by time of day", "Done/tried by gap length", "Fit ratings",
    "Morning walk 4.0", "Skipped in the last 14 days: Strength circuit - no energy", "none of these", "wrong length",
    "This week (7d) vs intention", "Last events", "rated poorly", "Avoid repeating the most recent activity",
    "not been suggested recently", "behind their weekly intention", '"based_on"']) {
    assertStringIncludes(prompt, s);
  }
});

Deno.test("Source B's prompt carries only the gap length and energy", async () => {
  const m = modelReturning(goodA, goodB);
  await generateCards(input(), deps(m.call));
  const prompt = m.prompts.find((p) => !isA(p))!;
  assertStringIncludes(prompt, "I have 20 minutes and energy level 2");
  for (const s of ["Morning walk", "Gentle stretch", "Feeling steady", "afternoon", "Tuesday", "14:00", "Wakes", "History", "America/New_York"]) {
    assert(!prompt.includes(s), `B prompt must not contain "${s}"`);
  }
});

Deno.test("the fallback pick follows priority, intention, recency and avoids the last activity", () => {
  const allowed = [walk, stretch, breathe, circuit].map((activity) => ({ activity, durationMin: 10 }));
  assertEquals(ruleBasedPick(allowed, input())!.activity.id, "walk"); // priority 3, behind its intention, never shown
  const justDid = input({ events: [event({ daysAgo: 0.1, gapLocal: "10:00", chosenActivityId: "walk", completed: true })] });
  assertEquals(ruleBasedPick(allowed, justDid)!.activity.id, "stretch");
  assertEquals(ruleBasedPick([], input()), null);
});
