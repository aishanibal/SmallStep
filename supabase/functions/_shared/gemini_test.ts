import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1.0.13";
import { geminiCaller, TEMPERATURE } from "./gemini.ts";

const fakeFetch = (status: number, body: unknown, seen: { url?: string; init?: RequestInit } = {}): typeof fetch =>
  ((url: string | URL | Request, init?: RequestInit) => {
    seen.url = String(url);
    seen.init = init;
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  }) as typeof fetch;

const ok = { candidates: [{ content: { parts: [{ text: '{"a":' }, { text: "1}" }] } }] };

Deno.test("sends a low-temperature JSON request; the key goes in a header only", async () => {
  const seen: { url?: string; init?: RequestInit } = {};
  const reply = await geminiCaller("SECRET-KEY", "model-x", fakeFetch(200, ok, seen))("hello");
  assertEquals(reply.text, '{"a":1}'); // parts are joined
  assertStringIncludes(seen.url!, "/models/model-x:generateContent");
  assert(!seen.url!.includes("SECRET-KEY"), "key must not be in the URL");
  assertEquals((seen.init!.headers as Record<string, string>)["x-goog-api-key"], "SECRET-KEY");
  const body = JSON.parse(String(seen.init!.body));
  assertEquals(body.generationConfig.temperature, TEMPERATURE);
  assert(TEMPERATURE <= 0.3);
  assertEquals(body.generationConfig.responseMimeType, "application/json");
  assertEquals(body.contents[0].parts[0].text, "hello");
  assert(!String(seen.init!.body).includes("SECRET-KEY"));
});

Deno.test("ignores thought parts", async () => {
  const body = { candidates: [{ content: { parts: [{ text: "thinking...", thought: true }, { text: "{}" }] } }] };
  assertEquals((await geminiCaller("k", "m", fakeFetch(200, body))("p")).text, "{}");
});

Deno.test("fails clearly when unconfigured, on HTTP errors, and on empty replies", async () => {
  await assertRejects(() => geminiCaller(undefined, "m")("p"), Error, "GEMINI_API_KEY");
  await assertRejects(() => geminiCaller("k", undefined)("p"), Error, "GEMINI_MODEL");
  await assertRejects(() => geminiCaller("k", "m", fakeFetch(429, {}), 1000, 0)("p"), Error, "http 429");
  await assertRejects(() => geminiCaller("k", "m", fakeFetch(400, {}), 1000, 0)("p"), Error, "http 400");
  await assertRejects(() => geminiCaller("k", "m", fakeFetch(200, { candidates: [] }))("p"), Error, "no text");
});

Deno.test("retries once when the model is overloaded, but not on other errors", async () => {
  const flaky = (statuses: number[], calls: { n: number }): typeof fetch =>
    (() => {
      const status = statuses[calls.n++];
      return Promise.resolve(new Response(JSON.stringify(status === 200 ? ok : {}), { status }));
    }) as typeof fetch;
  const c1 = { n: 0 };
  assertEquals((await geminiCaller("k", "m", flaky([503, 200], c1), 1000, 0)("p")).text, '{"a":1}');
  assertEquals(c1.n, 2);
  const c2 = { n: 0 };
  await assertRejects(() => geminiCaller("k", "m", flaky([400, 200], c2), 1000, 0)("p"), Error, "http 400");
  assertEquals(c2.n, 1);
});

Deno.test("asks for low thinking so replies arrive inside the timeout", async () => {
  const seen: { url?: string; init?: RequestInit } = {};
  await geminiCaller("k", "m", fakeFetch(200, ok, seen))("p");
  assertEquals(JSON.parse(String(seen.init!.body)).generationConfig.thinkingConfig, { thinkingLevel: "low" });
});
