import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json" },
});
const esc = (value: unknown) => String(value ?? "").replace(
  /[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!,
);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return json({ error: "Authentication required." }, 401);

    const { request_id } = await req.json();
    if (!Number.isInteger(Number(request_id))) return json({ error: "Invalid request id." }, 400);

    const admin = createClient(url, service);
    const { data: order, error: orderError } = await admin
      .from("redemption_requests")
      .select("*")
      .eq("id", request_id)
      .single();
    if (orderError || !order) return json({ error: "Order not found." }, 404);

    let allowed = order.user_id === user.id;
    if (!allowed) {
      const { data: adminRow } = await admin.from("admin_users").select("user_id").eq("user_id", user.id).maybeSingle();
      allowed = Boolean(adminRow);
    }
    if (!allowed) return json({ error: "You cannot notify this order." }, 403);

    const { data: profile } = await admin
      .from("profiles")
      .select("steam_id,username,contact_email,contact_email_verified_at")
      .eq("id", order.user_id)
      .maybeSingle();
    const { data: authUser } = await admin.auth.admin.getUserById(order.user_id);

    const resendKey = Deno.env.get("RESEND_API_KEY") || "";
    const adminEmail = Deno.env.get("ADMIN_REWARD_EMAIL") || "";
    const from = Deno.env.get("EMAIL_FROM") || "SkinQuest <orders@skinquestcs.com>";
    if (!resendKey || !adminEmail) return json({ error: "Email secrets are not configured; order remains saved." }, 503);

    const authEmail = String(authUser?.user?.email || "").trim().toLowerCase();
    const contactEmail = profile?.contact_email_verified_at
      ? String(profile?.contact_email || "").trim().toLowerCase()
      : "";
    const userEmail = contactEmail || (authEmail && !authEmail.endsWith("@steam.skinquestcs.com") ? authEmail : "");
    const orderNumber = order.order_number || `SQ-R-${String(order.id).padStart(6, "0")}`;
    const created = new Date(order.created_at).toLocaleString("sv-SE", { timeZone: "Europe/Stockholm" });
    const readyEstimate = order.estimated_ready_at
      ? new Date(order.estimated_ready_at).toLocaleString("sv-SE", { timeZone: "Europe/Stockholm" })
      : "Not set";
    const orderable = order.fulfillment_mode === "orderable";

    const send = async (to: string, subject: string, html: string) => {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from, to: [to], subject, html }),
      });
      if (!response.ok) throw new Error(`Resend returned ${response.status}`);
    };

    const adminHtml = `<h1>${orderable ? "New SkinQuest orderable reward" : "New SkinQuest in-stock reward"}</h1><table><tr><th>Order</th><td>${esc(orderNumber)}</td></tr><tr><th>User</th><td>${esc(userEmail || authEmail || "No contact email")} (${esc(order.user_id)})</td></tr><tr><th>Steam ID</th><td>${esc(profile?.steam_id || "Not connected")}</td></tr><tr><th>Reward</th><td>${esc(order.reward_name)}</td></tr><tr><th>Fulfilment</th><td>${orderable ? "AVAILABLE TO ORDER — purchase required" : "IN STOCK / PREPARED"}</td></tr><tr><th>Coin price</th><td>${esc(order.points_coins || order.points_cost)}</td></tr><tr><th>Time</th><td>${esc(created)}</td></tr><tr><th>Initial ETA</th><td>${esc(readyEstimate)}</td></tr><tr><th>Trade URL</th><td><a href="${esc(order.steam_trade_url)}">Open Steam trade URL</a></td></tr></table><p><a href="https://skinquestcs.com/admin?order=${encodeURIComponent(String(order.id))}">Open ${esc(orderNumber)} in admin</a></p>`;
    const userHtml = orderable
      ? `<h1>Your SkinQuest order is placed</h1><p>Your order for <strong>${esc(order.reward_name)}</strong> is saved as <strong>${esc(orderNumber)}</strong>.</p><p>${esc(order.points_coins || order.points_cost)} coins were deducted. This reward is <strong>Available to order</strong>, so SkinQuest will purchase it for fulfilment. After purchase, your dashboard will show the exact Steam trade-lock countdown.</p><p>Initial estimate: <strong>${esc(readyEstimate)}</strong>. This is an estimate until the item is purchased and Steam gives the exact unlock time.</p><p><a href="https://skinquestcs.com/dashboard?request=${encodeURIComponent(String(order.id))}">View order status</a></p>`
      : `<h1>Your reward is in stock</h1><p>Your order for <strong>${esc(order.reward_name)}</strong> is saved as <strong>${esc(orderNumber)}</strong>.</p><p>${esc(order.points_coins || order.points_cost)} coins were deducted and one prepared item was reserved for you. In-stock rewards are usually sent within 1–2 days.</p><p><a href="https://skinquestcs.com/dashboard?request=${encodeURIComponent(String(order.id))}">View order status</a></p>`;

    const jobs: Array<{ target: "admin" | "user"; promise: Promise<void> }> = [];
    if (!order.admin_notified_at) {
      jobs.push({
        target: "admin",
        promise: send(adminEmail, `${orderable ? "ORDER REQUIRED" : "IN-STOCK ORDER"} ${orderNumber}: ${order.reward_name}`, adminHtml),
      });
    }
    if (userEmail && !order.user_notified_at) {
      jobs.push({
        target: "user",
        promise: send(userEmail, orderable ? `SkinQuest order ${orderNumber} placed` : `SkinQuest ${orderNumber} ready for fulfilment`, userHtml),
      });
    }
    if (!jobs.length) return json({ ok: true, skipped: true, reason: "already_notified" });

    const results = await Promise.allSettled(jobs.map((job) => job.promise));
    const now = new Date().toISOString();
    let adminSent = Boolean(order.admin_notified_at);
    let userSent = Boolean(order.user_notified_at);
    const failures: string[] = [];

    results.forEach((result, index) => {
      const target = jobs[index].target;
      if (result.status === "fulfilled") {
        if (target === "admin") adminSent = true;
        if (target === "user") userSent = true;
      } else {
        failures.push(`${target}: ${result.reason instanceof Error ? result.reason.message : "send failed"}`);
      }
    });

    const update: Record<string, unknown> = {};
    if (!order.admin_notified_at && adminSent) update.admin_notified_at = now;
    if (!order.user_notified_at && userSent) update.user_notified_at = now;
    if (userSent || !userEmail) {
      update.last_user_notified_status = order.status;
      update.user_status_notified_at = now;
    }
    if ((userSent || !userEmail) && (adminSent || Boolean(order.admin_notified_at))) {
      update.last_notified_status = order.status;
      update.status_notified_at = now;
    }
    if (Object.keys(update).length) await admin.from("redemption_requests").update(update).eq("id", order.id);

    if (failures.length) return json({ error: "One or more emails failed; successful targets will not be resent.", failures }, 502);
    return json({ ok: true, fulfillment_mode: order.fulfillment_mode, status: order.status, admin_sent: adminSent, user_sent: userSent });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error." }, 500);
  }
});
