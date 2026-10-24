// Shared by the Edge Functions: JSON responses, the service-role client, and who is calling.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.49.4";

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** New projects expose SUPABASE_SECRET_KEYS (JSON); older ones only the legacy service-role variable. */
function secretKey(): string {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    const parsed = JSON.parse(keys) as Record<string, string>;
    return parsed.default ?? Object.values(parsed)[0];
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
}

export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false } });
}

/** The caller's user id from their access token, or null. Never trust a participant id from the body. */
export async function authenticate(req: Request, db: SupabaseClient): Promise<string | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const { data, error } = await db.auth.getUser(token);
  return error || !data?.user ? null : data.user.id;
}
