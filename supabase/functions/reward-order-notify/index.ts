import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const esc = (value: unknown) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        char
      ]!,
  );

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();
    if (authError || !user)
      return json({ error: "Authentication required." }, 401);

    const { request_id } = await req.json();
    if (!Number.isInteger(Number(request_id)))
      return json({ error: "Invalid request id." }, 400);
    const admin = createClient(url, service);
    const { data: order, error } = await admin
      .from("redemption_requests")
      .select("*")
      .eq("id", request_id)
      .eq("user_id", user.id)
      .single();
    if (error || !order) return json({ error: "Order not found." }, 404);
    const orderNumber =
      order.order_number || `SQ-R-${String(order.id).padStart(6, "0")}`;
    const { data: profile } = await admin
      .from("profiles")
      .select("steam_id,username,contact_email,contact_email_verified_at")
      .eq("id", user.id)
      .maybeSingle();

    const resendKey = Deno.env.get("RESEND_API_KEY");
    const adminEmail = Deno.env.get("ADMIN_REWARD_EMAIL");
    const from =
      Deno.env.get("EMAIL_FROM") || "SkinQuest <orders@skinquestcs.com>";
    if (!resendKey || !adminEmail)
      return json(
        { error: "Email secrets are not configured; order remains saved." },
        503,
      );
    const send = async (to: string, subject: string, html: string) => {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ from, to: [to], subject, html }),
      });
      if (!response.ok) throw new Error(`Resend returned ${response.status}`);
    };
    const created = new Date(order.created_at).toLocaleString("sv-SE", {
      timeZone: "Europe/Stockholm",
    });
    const authEmail = String(user.email || "").trim().toLowerCase();
    const contactEmail = profile?.contact_email_verified_at ? String(profile?.contact_email || "").trim().toLowerCase() : "";
    const userEmail = contactEmail || (authEmail && !authEmail.endsWith("@steam.skinquestcs.com") ? authEmail : "");
    const adminHtml = `<h1>New SkinQuest reward order</h1><table><tr><th>Order</th><td>${esc(orderNumber)}</td></tr><tr><th>User</th><td>${esc(userEmail || user.email || "No contact email")} (${esc(user.id)})</td></tr><tr><th>Steam ID</th><td>${esc(profile?.steam_id || "Not connected")}</td></tr><tr><th>Reward</th><td>${esc(order.reward_name)}</td></tr><tr><th>Coin price</th><td>${esc(order.points_coins || order.points_cost)}</td></tr><tr><th>Time</th><td>${esc(created)}</td></tr><tr><th>Trade URL</th><td><a href="${esc(order.steam_trade_url)}">Open Steam trade URL</a></td></tr></table><p><a href="https://skinquestcs.com/admin?order=${esc(order.id)}">Open ${esc(orderNumber)} in admin</a></p>`;
    const userHtml = `<h1>We received your reward request</h1><p>Your request for <strong>${esc(order.reward_name)}</strong> is saved as <strong>${esc(orderNumber)}</strong>.</p><p>${esc(order.points_coins || order.points_cost)} coins were deducted and the item was reserved for manual review.</p><p><a href="https://skinquestcs.com/dashboard?request=${esc(order.id)}">View request status</a></p>`;

    const emailJobs = [
      send(
        adminEmail,
        `New reward order ${orderNumber}: ${order.reward_name}`,
        adminHtml,
      ),
    ];
    if (userEmail) emailJobs.push(send(userEmail, `SkinQuest order ${orderNumber} received`, userHtml));
    const results = await Promise.allSettled(emailJobs);
    if (results[0].status === "fulfilled")
      await admin
        .from("redemption_requests")
        .update({ admin_notified_at: new Date().toISOString() })
        .eq("id", order.id);
    if (userEmail && results[1]?.status === "fulfilled")
      await admin
        .from("redemption_requests")
        .update({ user_notified_at: new Date().toISOString() })
        .eq("id", order.id);
    if (results.some((result) => result.status === "rejected"))
      return json(
        { error: "One or more emails failed; order remains saved." },
        502,
      );
    return json({ ok: true });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "Unexpected error." },
      500,
    );
  }
});
