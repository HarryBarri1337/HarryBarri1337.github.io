import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function sha256(value: string) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return json({ error: "Authentication required." }, 401);

    const body = await req.json().catch(() => ({}));
    const code = String(body.code || "").replace(/\D/g, "");
    if (!/^\d{6}$/.test(code)) return json({ error: "Enter the 6-digit verification code." }, 400);

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: row, error: rowError } = await admin
      .from("contact_email_verifications")
      .select("email,code_hash,expires_at,attempts")
      .eq("user_id", user.id)
      .maybeSingle();
    if (rowError) throw rowError;
    if (!row) return json({ error: "Request a new verification code first." }, 400);
    if (new Date(row.expires_at).getTime() < Date.now()) {
      await admin.from("contact_email_verifications").delete().eq("user_id", user.id);
      return json({ error: "That code expired. Request a new one." }, 400);
    }
    if (Number(row.attempts || 0) >= 5) {
      await admin.from("contact_email_verifications").delete().eq("user_id", user.id);
      return json({ error: "Too many incorrect attempts. Request a new code." }, 429);
    }

    const secret = Deno.env.get("CONTACT_EMAIL_SECRET") || serviceKey;
    const candidate = await sha256(`${secret}:${user.id}:${row.email}:${code}`);
    if (!safeEqual(candidate, String(row.code_hash || ""))) {
      await admin.from("contact_email_verifications").update({ attempts: Number(row.attempts || 0) + 1 }).eq("user_id", user.id);
      return json({ error: "Incorrect verification code." }, 400);
    }

    const verifiedAt = new Date().toISOString();
    const { error: updateError } = await admin
      .from("profiles")
      .update({ contact_email: row.email, contact_email_verified_at: verifiedAt, updated_at: verifiedAt })
      .eq("id", user.id);
    if (updateError) {
      if (String(updateError.message || "").toLowerCase().includes("duplicate")) {
        return json({ error: "That email is already used by another SkinQuest account." }, 409);
      }
      throw updateError;
    }

    await admin.from("contact_email_verifications").delete().eq("user_id", user.id);
    return json({ ok: true, email: row.email, verified_at: verifiedAt });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Unexpected error." }, 500);
  }
});
