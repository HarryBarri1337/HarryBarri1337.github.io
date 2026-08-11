import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const hash = async (value: string) =>
  Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  )
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json();
    if (body.website) return reply({ ok: true });
    const email = String(body.account_email || "")
      .trim()
      .toLowerCase();
    const topic = String(body.topic || "").trim();
    const message = String(body.message || "").trim();
    if (
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      email.length > 254 ||
      topic.length < 2 ||
      topic.length > 80 ||
      message.length < 8 ||
      message.length > 1800
    )
      return reply({ error: "Invalid support request." }, 400);
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const ip = (req.headers.get("x-forwarded-for") || "unknown")
      .split(",")[0]
      .trim();
    const keyHash = await hash(
      `${Deno.env.get("RATE_LIMIT_SECRET") || "skinquest"}:${ip}:${email}`,
    );
    const hour = new Date();
    hour.setUTCMinutes(0, 0, 0);
    const { data: rate } = await admin
      .from("support_rate_limits")
      .select("request_count")
      .eq("key_hash", keyHash)
      .eq("window_start", hour.toISOString())
      .maybeSingle();
    if ((rate?.request_count || 0) >= 5)
      return reply(
        { error: "Too many support requests. Try again later." },
        429,
      );
    await admin.from("support_rate_limits").upsert({
      key_hash: keyHash,
      window_start: hour.toISOString(),
      request_count: (rate?.request_count || 0) + 1,
    });
    let userId: string | null = null;
    const auth = req.headers.get("Authorization");
    if (auth) {
      const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: auth } },
      });
      const { data } = await userClient.auth.getUser();
      userId = data.user?.id || null;
    }
    let pageUrl: string | null = null;
    try {
      const parsed = new URL(String(body.page_url || ""));
      if (parsed.origin === "https://skinquestcs.com")
        pageUrl = parsed.toString().slice(0, 500);
    } catch {}
    const { error } = await admin.from("support_requests").insert({
      user_id: userId,
      topic,
      message,
      page_url: pageUrl,
      user_agent: (req.headers.get("user-agent") || "").slice(0, 500),
      account_email: email,
      browser_language: String(body.browser_language || "").slice(0, 50),
    });
    if (error) throw error;
    return reply({ ok: true });
  } catch (error) {
    return reply(
      { error: error instanceof Error ? error.message : "Unexpected error." },
      500,
    );
  }
});
