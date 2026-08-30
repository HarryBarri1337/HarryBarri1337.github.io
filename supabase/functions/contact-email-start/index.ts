import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (value: unknown) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
}[char]!));

async function sha256(value: string) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function generateCode() {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1_000_000).padStart(6, "0");
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
    const email = String(body.email || "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || email.length > 254) {
      return json({ error: "Enter a valid email address." }, 400);
    }
    if (email.endsWith("@steam.skinquestcs.com")) {
      return json({ error: "Enter a real email address you can access." }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey);

    const { data: usedContact } = await admin
      .from("profiles")
      .select("id")
      .eq("contact_email", email)
      .not("contact_email_verified_at", "is", null)
      .neq("id", user.id)
      .maybeSingle();
    if (usedContact?.id) return json({ error: "That email is already used by another SkinQuest account." }, 409);

    // SkinQuest is currently small enough that this protects against choosing another account's auth email too.
    const { data: authUsers } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    const authEmailOwner = authUsers?.users?.find((candidate) =>
      candidate.id !== user.id && String(candidate.email || "").trim().toLowerCase() === email
    );
    if (authEmailOwner) return json({ error: "That email is already used by another SkinQuest account." }, 409);

    const { data: previous } = await admin
      .from("contact_email_verifications")
      .select("sent_at")
      .eq("user_id", user.id)
      .maybeSingle();
    if (previous?.sent_at && Date.now() - new Date(previous.sent_at).getTime() < 60_000) {
      return json({ error: "A code was just sent. Wait a minute before requesting another." }, 429);
    }

    const code = generateCode();
    const secret = Deno.env.get("CONTACT_EMAIL_SECRET") || serviceKey;
    const codeHash = await sha256(`${secret}:${user.id}:${email}:${code}`);
    const expiresAt = new Date(Date.now() + 10 * 60_000).toISOString();

    const { error: saveError } = await admin.from("contact_email_verifications").upsert({
      user_id: user.id,
      email,
      code_hash: codeHash,
      expires_at: expiresAt,
      sent_at: new Date().toISOString(),
      attempts: 0,
    }, { onConflict: "user_id" });
    if (saveError) throw saveError;

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      await admin.from("contact_email_verifications").delete().eq("user_id", user.id);
      return json({ error: "Email delivery is not configured yet." }, 503);
    }
    const from = Deno.env.get("EMAIL_FROM") || "SkinQuest <no-reply@skinquestcs.com>";
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from,
        to: [email],
        subject: "Your SkinQuest verification code",
        html: `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto"><h1>Verify your SkinQuest email</h1><p>Enter this code on SkinQuest:</p><p style="font-size:32px;font-weight:800;letter-spacing:8px">${esc(code)}</p><p>This code expires in 10 minutes.</p><p>If you did not request this, you can ignore this email.</p></div>`,
      }),
    });
    if (!response.ok) {
      await admin.from("contact_email_verifications").delete().eq("user_id", user.id);
      const details = await response.text().catch(() => "");
      console.error("Contact email send failed", response.status, details);
      return json({ error: "Could not send the verification email. Try again shortly." }, 502);
    }

    return json({ ok: true, expires_in: 600 });
  } catch (error) {
    console.error(error);
    return json({ error: error instanceof Error ? error.message : "Unexpected error." }, 500);
  }
});
