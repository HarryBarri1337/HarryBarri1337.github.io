import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function safeRedirect(value: unknown) {
  const fallback = "https://skinquestcs.com/auth-confirm?mode=recovery";
  try {
    const url = new URL(String(value || fallback));
    if (url.origin !== "https://skinquestcs.com") return fallback;
    if (!/^\/{1,2}auth-confirm\/?$/.test(url.pathname)) return fallback;
    url.pathname = "/auth-confirm";
    url.search = "?mode=recovery";
    url.hash = "";
    return url.toString();
  } catch {
    return fallback;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  let keyHash = "";

  try {
    const body = await req.json().catch(() => ({}));
    const email = String(body.email || "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || email.length > 254) {
      return json({ error: "Enter a valid email address." }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const rateSecret = Deno.env.get("RATE_LIMIT_SECRET") || serviceKey;
    keyHash = await sha256(`${rateSecret}:password-reset:${email}`);

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: retryAfter, error: rateError } = await admin.rpc(
      "claim_password_reset_rate_limit",
      { p_key_hash: keyHash },
    );
    if (rateError) throw rateError;

    const retrySeconds = Math.max(0, Number(retryAfter) || 0);
    if (retrySeconds > 0) {
      return json(
        {
          error: `Please wait ${retrySeconds} second${retrySeconds === 1 ? "" : "s"} before requesting another reset email.`,
          retry_after: retrySeconds,
        },
        429,
      );
    }

    const authClient = createClient(supabaseUrl, anonKey);
    const { error: resetError } = await authClient.auth.resetPasswordForEmail(email, {
      redirectTo: safeRedirect(body.redirect_to),
    });

    if (resetError) {
      // Do not consume SkinQuest's one-minute cooldown when Supabase itself
      // could not accept the reset request.
      await admin.from("password_reset_rate_limits").delete().eq("key_hash", keyHash);
      console.error("Password reset request failed", resetError.message);
      return json({ error: "Could not send the reset email. Try again shortly." }, 502);
    }

    return json({ ok: true, retry_after: 60 });
  } catch (error) {
    console.error(error);
    return json({ error: "Could not send the reset email. Try again shortly." }, 500);
  }
});
