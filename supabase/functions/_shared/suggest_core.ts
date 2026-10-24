// Builds the cards for one gap: Source A (context, model-written), B (generic), C (static), then merge, shuffle.
// Pure apart from the injected model caller and random function, so it is fully unit-tested.
import { allowedActivities, checkCandidate } from "./filters.ts";
import { buildHistorySummary, doneInWindow, HISTORY_CONFIG, lastShownMap } from "./history.ts";
import { type Allowed, buildPromptA, buildPromptB, parseA, parseB } from "./prompts.ts";
import type { ModelCaller } from "./gemini.ts";
import type { Activity, Gap, HistoryEvent, Profile, ShownRecord } from "./types.ts";

export type Source = "A" | "A_fallback" | "B" | "C";

export interface Card {
  sources: Source[]; // more than one when two sources picked the same activity
  activityId: string | null;
  title: string;
  description: string;
  durationMin: number;
  reasonText: string | null;
  promptSnapshot: string | null;
  model: string | null;
  latencyMs: number | null;
  error: string | null;
  position: number;
}

export interface SuggestInput {
  profile: Profile;
  activities: Activity[];
  gap: Gap;
  events: HistoryEvent[];
  shown: ShownRecord[];
  now: Date;
}
export interface Deps {
  callModel: ModelCaller;
  modelName: string | null;
  rng: () => number;
}

/** Plain ideas that stand in for Source B when its model call fails or breaks a rule. Not from the user's list. */
export const GENERIC_IDEAS = [
  { title: "Slow breathing", description: "Breathe in for four, out for six, a few times.", durationMin: 3 },
  { title: "Stretch break", description: "Roll your shoulders and reach your arms overhead.", durationMin: 5 },
  { title: "Water and a pause", description: "Have a glass of water and look away from screens.", durationMin: 5 },
  { title: "Short walk", description: "A relaxed walk, indoors or out.", durationMin: 10 },
  { title: "Quiet sit", description: "Sit somewhere comfortable and let your mind settle.", durationMin: 15 },
  { title: "Gentle walk", description: "An unhurried walk, no destination needed.", durationMin: 20 },
];

const plainLine = (a: Activity) => `A ${a.category.trim().toLowerCase()} activity from your list.`;
const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e)).slice(0, 200);

function shuffle<T>(items: T[], rng: () => number): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/** Rule-based stand-in for Source A: priority, behind-intention, not shown lately, not the last activity. */
export function ruleBasedPick(allowed: Allowed[], input: SuggestInput): Allowed | null {
  if (allowed.length === 0) return null;
  const done = doneInWindow(input.events, input.now, HISTORY_CONFIG.intentionWindowDays);
  const lastShown = lastShownMap(input.shown);
  const lastChosen = [...input.events]
    .sort((a, b) => new Date(b.ts).getTime() - new Date(a.ts).getTime())
    .find((e) => e.chosenActivityId)?.chosenActivityId;
  const score = ({ activity: a }: Allowed) => {
    const behind = a.weekly_intention !== null && (done.get(a.id) ?? 0) < a.weekly_intention;
    const last = lastShown.get(a.id);
    const stale = last === undefined || input.now.getTime() - last >= HISTORY_CONFIG.notSuggestedDays * 86400000;
    return a.priority * 2 + (behind ? 1.5 : 0) + (stale ? 1 : 0) - (a.id === lastChosen ? 2 : 0);
  };
  return [...allowed].sort((x, y) => score(y) - score(x) || x.activity.name.localeCompare(y.activity.name))[0];
}

/** Source A: the model writes a suggestion tailored to this person. Falls back to a rule-based pick. */
async function sourceA(input: SuggestInput, allowed: Allowed[], history: string[], deps: Deps): Promise<Omit<Card, "position"> | null> {
  if (input.activities.length === 0) return null;
  const prompt = buildPromptA(input.profile, input.gap, input.activities, history);
  const base = { promptSnapshot: prompt, model: deps.modelName };
  try {
    const reply = await deps.callModel(prompt);
    const a = parseA(reply.text, input.gap, input.profile, input.activities);
    return {
      ...base, sources: ["A"], activityId: a.basedOn?.id ?? null, title: a.title, description: a.description,
      durationMin: a.durationMin, reasonText: a.reason, latencyMs: reply.latencyMs, error: null,
    };
  } catch (e) {
    const pick = ruleBasedPick(allowed, input);
    if (!pick) return null;   // nothing of theirs fits this gap
    return {
      ...base, sources: ["A_fallback"], activityId: pick.activity.id, title: pick.activity.name,
      description: plainLine(pick.activity), durationMin: pick.durationMin, reasonText: null, latencyMs: null, error: errorText(e),
    };
  }
}

async function sourceB(input: SuggestInput, deps: Deps): Promise<Omit<Card, "position"> | null> {
  const prompt = buildPromptB(input.gap);
  const base = { sources: ["B"] as Source[], activityId: null, reasonText: null, promptSnapshot: prompt, model: deps.modelName };
  let error: string;
  let latencyMs: number | null = null;
  try {
    const reply = await deps.callModel(prompt);
    latencyMs = reply.latencyMs;
    const b = parseB(reply.text, input.gap, input.profile);
    return { ...base, title: b.title, description: b.description, durationMin: b.durationMin, latencyMs, error: null };
  } catch (e) {
    error = errorText(e);
  }
  // Still show something for B: a generic idea that passes the same hard filters.
  const options = GENERIC_IDEAS.filter((i) =>
    checkCandidate({ durationMin: i.durationMin, text: `${i.title} ${i.description}` }, input.gap, input.profile).ok
  );
  if (options.length === 0) return null;
  const idea = options[Math.floor(deps.rng() * options.length)];
  return { ...base, title: idea.title, description: idea.description, durationMin: idea.durationMin, latencyMs, error };
}

/** Source C: a random fitting activity, avoiding the one A built on when another fits (so there are three cards). */
function sourceC(allowed: Allowed[], deps: Deps, avoidID: string | null): Omit<Card, "position"> | null {
  if (allowed.length === 0) return null;
  const others = allowed.filter((x) => x.activity.id !== avoidID);
  const pool = others.length > 0 ? others : allowed;
  const { activity: a, durationMin } = pool[Math.floor(deps.rng() * pool.length)];
  return {
    sources: ["C"], activityId: a.id, title: a.name, description: plainLine(a), durationMin,
    reasonText: null, promptSnapshot: null, model: null, latencyMs: null, error: null,
  };
}

export async function generateCards(input: SuggestInput, deps: Deps): Promise<{ cards: Card[]; historySummary: string[] }> {
  const allowed = allowedActivities(input.activities, input.gap, input.profile);
  const historySummary = buildHistorySummary({
    activities: input.activities, events: input.events, shown: input.shown, now: input.now, timezone: input.profile.timezone,
  });

  const [a, b] = await Promise.all([sourceA(input, allowed, historySummary, deps), sourceB(input, deps)]);
  const c = sourceC(allowed, deps, a?.activityId ?? null);

  // Same activity from two sources (A suggested exactly C's activity): show it once, credit both.
  const same = !!(a && c && a.activityId !== null && a.activityId === c.activityId &&
    a.title.trim().toLowerCase() === c.title.trim().toLowerCase());
  if (same) a!.sources = [...a!.sources, "C"];
  const picked = [a, b, same ? null : c].filter((x): x is Omit<Card, "position"> => x !== null);
  const cards = shuffle(picked, deps.rng).map((card, position) => ({ ...card, position }));
  return { cards, historySummary };
}

/** What the app is allowed to see: no sources, reasons, prompts, models or errors. */
export function toPublicCard(card: Card, id: string) {
  return { id, title: card.title, description: card.description, duration_min: card.durationMin, position: card.position };
}
