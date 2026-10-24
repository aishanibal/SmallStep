// Gemini over plain REST (generateContent). Only ever imported by Edge Functions: the key stays in
// the Supabase secret GEMINI_API_KEY and never reaches the app.

export interface ModelReply {
  text: string;
  latencyMs: number;
}
/** Sends one prompt, returns the model's text. Throws on any failure. */
export type ModelCaller = (prompt: string) => Promise<ModelReply>;

export const TEMPERATURE = 0.2; // low for both A and B

export function geminiCaller(
  apiKey: string | undefined,
  model: string | undefined,
  fetchImpl: typeof fetch = fetch,
  timeoutMs = 15000,
): ModelCaller {
  return async (prompt) => {
    if (!apiKey) throw new Error("GEMINI_API_KEY is not set");
    if (!model) throw new Error("GEMINI_MODEL is not set");
    const started = performance.now();
    const res = await fetchImpl(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: { temperature: TEMPERATURE, responseMimeType: "application/json", maxOutputTokens: 4096 },
        }),
        signal: AbortSignal.timeout(timeoutMs),
      },
    );
    if (!res.ok) throw new Error(`gemini http ${res.status}`);
    const json = await res.json();
    // The reply can have several parts (and "thought" parts); join the visible text.
    const parts: { text?: string; thought?: boolean }[] = json?.candidates?.[0]?.content?.parts ?? [];
    const text = parts.filter((p) => !p.thought && typeof p.text === "string").map((p) => p.text).join("");
    if (!text.trim()) throw new Error("gemini returned no text");
    return { text, latencyMs: Math.round(performance.now() - started) };
  };
}
