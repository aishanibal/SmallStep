import { assert, assertEquals } from "jsr:@std/assert@1.0.13";
import { allowedActivities, checkCandidate, pickDuration } from "./filters.ts";
import { MEAL_RULES } from "./filters.config.ts";
import { activities, circuit, gapAt, profile, walk } from "./fixtures.ts";

const reason = (v: ReturnType<typeof checkCandidate>) => (v.ok ? "ok" : v.reason);

Deno.test("fits the gap", () => {
  assertEquals(reason(checkCandidate({ durationMin: 20, category: "yoga" }, gapAt("10:00", 20), profile)), "ok");
  assertEquals(reason(checkCandidate({ durationMin: 21, category: "yoga" }, gapAt("10:00", 20), profile)), "too_long");
});

Deno.test("stays within waking hours", () => {
  assertEquals(reason(checkCandidate({ durationMin: 10, category: "yoga" }, gapAt("06:30", 30), profile)), "outside_waking_hours"); // before wake (also quiet)
  assertEquals(reason(checkCandidate({ durationMin: 30, category: "yoga" }, gapAt("07:00", 30), profile)), "ok");                    // starts exactly at wake
  assertEquals(reason(checkCandidate({ durationMin: 30, category: "yoga" }, gapAt("21:45", 60), profile)), "quiet_hours");          // runs into 22:00 quiet
});

Deno.test("bedtime after midnight is handled", () => {
  const late = { ...profile, bedtime: "01:00", quiet_start: "01:00", quiet_end: "07:00" };
  assertEquals(reason(checkCandidate({ durationMin: 30, category: "yoga" }, gapAt("23:30", 60), late)), "ok");
  assertEquals(reason(checkCandidate({ durationMin: 45, category: "yoga" }, gapAt("00:30", 60), late)), "outside_waking_hours");
});

Deno.test("quiet hours that wrap midnight block both sides", () => {
  const p = { ...profile, bedtime: "23:59" };
  assertEquals(reason(checkCandidate({ durationMin: 10, category: "yoga" }, gapAt("22:10", 30), p)), "quiet_hours");
  assertEquals(reason(checkCandidate({ durationMin: 10, category: "yoga" }, gapAt("21:50", 30), p)), "ok");
  assertEquals(reason(checkCandidate({ durationMin: 10, category: "yoga" }, gapAt("07:00", 30), p)), "ok"); // quiet ends at 07:00
});

Deno.test("quiet_start == quiet_end means no quiet hours", () => {
  const p = { ...profile, quiet_start: "22:00", quiet_end: "22:00" };
  assertEquals(reason(checkCandidate({ durationMin: 30, category: "yoga" }, gapAt("22:15", 30), p)), "ok");
});

Deno.test("high intensity is blocked for 60 minutes after a meal, others are not", () => {
  const strength = { durationMin: 15, category: "Strength" }; // case-insensitive
  assertEquals(reason(checkCandidate(strength, gapAt("12:30", 30), profile)), "after_meal");
  assertEquals(reason(checkCandidate(strength, gapAt("13:15", 30), profile)), "after_meal");
  assertEquals(reason(checkCandidate(strength, gapAt("13:30", 30), profile)), "ok");   // window is [meal, meal+60)
  assertEquals(reason(checkCandidate({ durationMin: 15, category: "yoga" }, gapAt("12:30", 30), profile)), "ok");
  // overlap counts too: starts before the meal but runs into it
  assertEquals(reason(checkCandidate({ durationMin: 41, category: "running" }, gapAt("11:50", 60), profile)), "after_meal");
  assertEquals(reason(checkCandidate({ durationMin: 40, category: "running" }, gapAt("11:50", 60), profile)), "ok"); // ends as lunch starts
});

Deno.test("meal window is configurable", () => {
  const rules = { ...MEAL_RULES, minutesAfterMeal: 30 };
  assertEquals(reason(checkCandidate({ durationMin: 15, category: "strength" }, gapAt("13:05", 30), profile, rules)), "ok");
  assertEquals(reason(checkCandidate({ durationMin: 15, category: "strength" }, gapAt("13:05", 30), profile)), "after_meal");
});

Deno.test("Source B text without a category is checked by keywords", () => {
  assertEquals(reason(checkCandidate({ durationMin: 15, text: "Go for a quick jog around the block" }, gapAt("08:10", 30), profile)), "after_meal");
  assertEquals(reason(checkCandidate({ durationMin: 15, text: "Sit and breathe slowly" }, gapAt("08:10", 30), profile)), "ok");
});

Deno.test("an activity is offered at its one duration, only if it fits and passes the filters", () => {
  assertEquals(pickDuration(walk, gapAt("10:00", 45), profile), 20);
  assertEquals(pickDuration(walk, gapAt("10:00", 20), profile), 20);
  assertEquals(pickDuration(walk, gapAt("10:00", 19), profile), null);          // longer than the gap
  assertEquals(pickDuration(circuit, gapAt("13:00", 45), profile), null);       // strength inside the lunch window
  assertEquals(pickDuration(circuit, gapAt("14:00", 45), profile), 15);
});

Deno.test("when nothing fits at its usual length, shortened versions are offered (still filtered)", () => {
  const got = allowedActivities([walk, circuit], gapAt("10:00", 8), profile).map((x) => [x.activity.id, x.durationMin]);
  assertEquals(got, [["walk", 8], ["circuit", 8]]);
  // inside the lunch window a strength activity stays out even when shortened
  assertEquals(allowedActivities([circuit], gapAt("12:40", 8), profile), []);
  // nothing below 5 minutes
  assertEquals(allowedActivities([walk], gapAt("10:00", 4), profile), []);
});

Deno.test("allowedActivities returns only the fitting ones with their durations", () => {
  const got = allowedActivities(activities, gapAt("10:00", 12), profile).map((x) => [x.activity.id, x.durationMin]);
  assertEquals(got, [["stretch", 10], ["breathe", 5]]); // walk (20) and circuit (15) are longer than the 12-minute gap
  assert(!got.some(([id]) => id === "circuit"));
});
