import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json" },
});
const esc = (value: unknown) => String(value ?? "").replace(
  /[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!,
);
const stockholm = (value: string | null | undefined) => value
  ? new Date(value).toLocaleString("sv-SE", { timeZone: "Europe/Stockholm" })
  : "Not set";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if(req.method!=="POST")return json({error:"POST required."},405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) return json({ error: "Authentication required." }, 401);

    const admin = createClient(url, service);
    const { data: adminRow } = await admin.from("admin_users").select("user_id,role").eq("user_id", user.id).maybeSingle();
    if (!adminRow) return json({ error: "Admin access required." }, 403);

    const { request_id } = await req.json();
    if (!Number.isInteger(Number(request_id))) return json({ error: "Invalid request id." }, 400);

    const { data: order, error: orderError } = await admin.from("redemption_requests").select("*").eq("id", request_id).single();
    if (orderError || !order) return json({ error: "Order not found." }, 404);

    const { data: profile } = await admin
      .from("profiles")
      .select("contact_email,contact_email_verified_at,steam_id,username")
      .eq("id", order.user_id)
      .maybeSingle();
    const { data: authUser } = await admin.auth.admin.getUserById(order.user_id);
    const authEmail = String(authUser?.user?.email || "").trim().toLowerCase();
    const contactEmail = profile?.contact_email_verified_at ? String(profile?.contact_email || "").trim().toLowerCase() : "";
    const userEmail = contactEmail || (authEmail && !authEmail.endsWith("@steam.skinquestcs.com") ? authEmail : "");

    const resendKey = Deno.env.get("RESEND_API_KEY") || "";
    const adminEmail = Deno.env.get("ADMIN_REWARD_EMAIL") || "";
    const from = Deno.env.get("EMAIL_FROM") || "SkinQuest <orders@skinquestcs.com>";
    if (!resendKey) return json({ error: "Email secret is not configured." }, 503);

    const send = async (to: string, subject: string, html: string, key?: string) => {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json", ...(key ? {"Idempotency-Key":key} : {}) },
        body: JSON.stringify({ from, to: [to], subject, html }),
      });
      if (!response.ok) throw new Error(`Resend returned ${response.status}`);
    };

    if(order.delivery_id){
      const {data:delivery,error:deliveryError}=await admin.from("sq_deliveries").select("*").eq("id",order.delivery_id).single();
      const {data:items,error:itemsError}=await admin.from("redemption_requests")
        .select("id,order_number,reward_name,points_coins,status,trade_locked_until,trade_offer_url,customer_note,fulfillment_mode,ready_admin_notified_at")
        .eq("delivery_id",order.delivery_id).eq("user_id",order.user_id).order("id");
      if(deliveryError||itemsError||!delivery||!items?.length)throw new Error("Could not load delivery notification snapshot.");
      // Stable content hash plus Resend idempotency protects concurrent retries.
      const snapshot=JSON.stringify(items.map(i=>[i.id,i.status,i.trade_locked_until,i.trade_offer_url,i.customer_note]));
      const bytes=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(snapshot));
      const signature=[...new Uint8Array(bytes)].map(b=>b.toString(16).padStart(2,"0")).join("");
      const ref=String(order.delivery_id).slice(0,8);
      const rows=items.map(i=>`<li><strong>${esc(i.reward_name)}</strong> — ${esc(i.order_number)} · ${esc(i.points_coins)} coins<br />Status: ${esc(i.status.replaceAll("_"," "))}${i.status==="trade_locked"?`<br />Recorded unlock: ${esc(stockholm(i.trade_locked_until))}`:""}${i.customer_note?`<p>${esc(i.customer_note)}</p>`:""}<br /><a href="https://skinquestcs.com/orders/${Number(i.id)}">View this order</a></li>`).join("");
      const html=`<h1>Your SkinQuest delivery update</h1><p>Delivery <strong>#${esc(ref)}</strong> contains ${items.length} orders. Each keeps its original saved coin price.</p><ul>${rows}</ul><p>A trade lock countdown records when an item is expected to become tradable, not a guaranteed sending time. Check the items in a Steam offer before accepting. SkinQuest never needs your Steam password or Guard code.</p><p><a href="https://skinquestcs.com/orders">View all orders and deliveries</a></p>`;
      const update:Record<string,unknown>={};
      if(userEmail&&delivery.user_notice_signature!==signature){
        await send(userEmail,`SkinQuest delivery #${ref} updated`,html,`sq-delivery-user-${order.delivery_id}-${signature}`);
        update.user_notice_signature=signature;
        for(const i of items){const {error}=await admin.from("redemption_requests")
          .update({last_user_notified_status:i.status,user_status_notified_at:new Date().toISOString()}).eq("id",i.id).eq("status",i.status);
          if(error)throw new Error("Email sent; order marker could not be saved. Retry is idempotent.");}
        const {error}=await admin.from("sq_deliveries").update(update).eq("id",order.delivery_id);
        if(error)throw new Error("Email sent; delivery marker could not be saved. Retry is idempotent.");
      }
      const ready=items.filter(i=>i.status==="ready_to_trade"&&i.fulfillment_mode==="orderable"&&!i.ready_admin_notified_at);
      if(ready.length&&adminEmail&&delivery.admin_notice_signature!==signature){
        const readyCount=items.filter(i=>i.status==="ready_to_trade"&&i.fulfillment_mode==="orderable").length;
        await send(adminEmail,`READY TO TRADE: delivery #${ref}`,`<h1>Delivery ready for fulfilment</h1><p>${readyCount} items are ready for staff to send.</p><ul>${rows}</ul><p><a href="https://skinquestcs.com/admin#deliveries">Open shared deliveries</a></p>`,`sq-delivery-admin-${order.delivery_id}-${signature}`);
        for(const i of ready){const {error}=await admin.from("redemption_requests").update({ready_admin_notified_at:new Date().toISOString()}).eq("id",i.id).eq("status","ready_to_trade");if(error)throw new Error("Ready email sent; marker could not be saved.");}
        const {error}=await admin.from("sq_deliveries").update({admin_notice_signature:signature}).eq("id",order.delivery_id);if(error)throw new Error("Ready email sent; delivery marker could not be saved.");
      }
      return json({ok:true,grouped:true,delivery_id:order.delivery_id});
    }

    const orderNumber = order.order_number || `SQ-R-${String(order.id).padStart(6, "0")}`;
    const dashboard = `https://skinquestcs.com/dashboard?request=${encodeURIComponent(String(order.id))}`;
    const adminUrl = `https://skinquestcs.com/admin?order=${encodeURIComponent(String(order.id))}`;

    let userSubject = `SkinQuest order ${orderNumber} updated`;
    let userHtml = `<h1>Order update</h1><p>Your order <strong>${esc(orderNumber)}</strong> for <strong>${esc(order.reward_name)}</strong> is now <strong>${esc(String(order.status).replaceAll("_", " "))}</strong>.</p><p><a href="${dashboard}">View order</a></p>`;

    if (order.status === "trade_locked") {
      userSubject = `SkinQuest ${orderNumber}: trade-lock countdown started`;
      userHtml = `<h1>Your skin has been purchased</h1><p>We bought <strong>${esc(order.reward_name)}</strong> for order <strong>${esc(orderNumber)}</strong>.</p><p>Steam has it trade locked until <strong>${esc(stockholm(order.trade_locked_until))}</strong>. Your dashboard now shows a live countdown.</p><p><a href="${dashboard}">View countdown</a></p>`;
    } else if (order.status === "ready_to_trade") {
      userSubject = `SkinQuest ${orderNumber}: ready to trade`;
      userHtml = `<h1>Your reward is ready to trade</h1><p><strong>${esc(order.reward_name)}</strong> is unlocked and ready for SkinQuest to send.</p><p>You do not need to place another order. Keep an eye on your Steam trade offers and your SkinQuest dashboard.</p><p><a href="${dashboard}">View order</a></p>`;
    } else if (order.status === "trade_sent") {
      userSubject = `SkinQuest ${orderNumber}: Steam trade sent`;
      userHtml = `<h1>Your Steam trade has been sent</h1><p>The trade offer for <strong>${esc(order.reward_name)}</strong> is ready.</p>${order.trade_offer_url ? `<p><a href="${esc(order.trade_offer_url)}">Open Steam trade offer</a></p>` : ""}<p><a href="${dashboard}">View order</a></p>`;
    } else if (order.status === "completed") {
      userSubject = `SkinQuest ${orderNumber}: completed`;
      userHtml = `<h1>Order completed</h1><p>Your reward order for <strong>${esc(order.reward_name)}</strong> is complete.</p><p><a href="${dashboard}">View order history</a></p>`;
    } else if (["rejected", "refunded", "cancelled"].includes(order.status)) {
      userSubject = `SkinQuest ${orderNumber}: ${String(order.status).replaceAll("_", " ")}`;
      userHtml = `<h1>Order ${esc(String(order.status).replaceAll("_", " "))}</h1><p>Your order for <strong>${esc(order.reward_name)}</strong> is now <strong>${esc(order.status)}</strong>.</p><p>If coins were held for this order, SkinQuest's server workflow handles the refund once.</p><p><a href="${dashboard}">View order</a></p>`;
    }

    const userNeeds = order.last_user_notified_status !== order.status;
    const adminReadyNeeds = order.status === "ready_to_trade" && order.fulfillment_mode === "orderable" && !order.ready_admin_notified_at;
    const jobs: Array<{ target: "user" | "admin_ready"; promise: Promise<void> }> = [];

    if (userNeeds && userEmail) jobs.push({ target: "user", promise: send(userEmail, userSubject, userHtml) });
    if (adminReadyNeeds && adminEmail) jobs.push({
      target: "admin_ready",
      promise: send(adminEmail, `READY TO TRADE ${orderNumber}: ${order.reward_name}`, `<h1>Reward ready to trade</h1><p><strong>${esc(orderNumber)}</strong> — ${esc(order.reward_name)}</p><p>The trade lock has ended. Send the customer trade offer.</p><p><a href="${adminUrl}">Open order in admin</a></p>`),
    });

    const now = new Date().toISOString();
    const update: Record<string, unknown> = {};
    if (userNeeds && !userEmail) {
      update.last_user_notified_status = order.status;
      update.user_status_notified_at = now;
    }
    if (adminReadyNeeds && !adminEmail) {
      // Keep ready_admin_notified_at null so this remains retryable once configured.
    }

    if (!jobs.length) {
      if (Object.keys(update).length) await admin.from("redemption_requests").update(update).eq("id", order.id).eq("status", order.status);
      return json({ ok: true, skipped: true, reason: "already_notified_or_no_target" });
    }

    const results = await Promise.allSettled(jobs.map((job) => job.promise));
    const failures: string[] = [];
    results.forEach((result, index) => {
      const target = jobs[index].target;
      if (result.status === "fulfilled") {
        if (target === "user") {
          update.last_user_notified_status = order.status;
          update.user_status_notified_at = now;
        } else if (target === "admin_ready") {
          update.ready_admin_notified_at = now;
        }
      } else {
        failures.push(`${target}: ${result.reason instanceof Error ? result.reason.message : "send failed"}`);
      }
    });

    const userDone = !userNeeds || !userEmail || update.last_user_notified_status === order.status;
    const adminDone = !adminReadyNeeds || Boolean(order.ready_admin_notified_at) || Boolean(update.ready_admin_notified_at);
    if (userDone && adminDone) {
      update.last_notified_status = order.status;
      update.status_notified_at = now;
    }
    if (Object.keys(update).length) await admin.from("redemption_requests").update(update).eq("id", order.id).eq("status", order.status);

    if (failures.length) return json({ error: "One or more status emails failed; successful targets will not be resent.", failures }, 502);
    return json({ ok: true, status: order.status });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected error." }, 500);
  }
});
