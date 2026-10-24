import { assertEquals } from "jsr:@std/assert@1.0.13";
import { assembleHistory } from "./data.ts";

Deno.test("joins outcomes, sets and suggestions into history events and shown cards", () => {
  const sets = [
    { id: "s1", created_at: "2026-03-09T14:00:00Z", gap: { start_time: "2026-03-09T14:00:00Z", minutes: 20 } },
    { id: "s2", created_at: "2026-03-10T14:00:00Z", gap: { start_time: "2026-03-10T14:00:00Z", minutes: 30 } },
    { id: "s3", created_at: "2026-03-10T15:00:00Z", gap: null }, // gap missing: ignored for events
  ];
  const suggestions = [
    { id: "g1", set_id: "s1", activity_id: "walk", title: "Morning walk" },
    { id: "g2", set_id: "s1", activity_id: null, title: "Slow breathing" },
    { id: "g3", set_id: "s2", activity_id: "stretch", title: "Gentle stretch" },
  ];
  const outcomes = [
    { set_id: "s1", chosen_suggestion_id: "g2", none_reason: null, completed: true, skip_reason: null, ts: "2026-03-09T14:05:00Z" },
    { set_id: "s2", chosen_suggestion_id: null, none_reason: "not_now", completed: null, skip_reason: null, ts: "2026-03-10T14:01:00Z" },
    { set_id: "s3", chosen_suggestion_id: null, none_reason: "x", completed: null, skip_reason: null, ts: "2026-03-10T15:01:00Z" },
  ];
  const { events, shown } = assembleHistory(outcomes, sets, suggestions);
  assertEquals(events.length, 2);
  assertEquals([events[0].chosenActivityId, events[0].chosenTitle, events[0].completed, events[0].isNone], [null, "Slow breathing", true, false]);
  assertEquals([events[1].isNone, events[1].noneReason, events[1].gapMinutes], [true, "not_now", 30]);
  assertEquals(shown, [
    { ts: "2026-03-09T14:00:00Z", activityId: "walk" },
    { ts: "2026-03-10T14:00:00Z", activityId: "stretch" },
  ]);
});
