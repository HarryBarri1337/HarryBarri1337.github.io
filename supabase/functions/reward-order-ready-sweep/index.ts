import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" },
});
const esc = (value: unknown) => String(value ?? "").replace(
  /[&<>"']/g,
  (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const configuredSecret = Deno.env.get("ORDER_CRON_SECRET") || "";
  const suppliedSecret = req.headers.get("x-cron-secret") || "";
  if (!configuredSecret || suppliedSecret !== configuredSecret) {
    return json({ error: "Cron authorization failed." }, 401);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const resendKey = Deno.env.get("RESEND_API_KEY") || "";
    const adminEmail = Deno.env.get("ADMIN_REWARD_EMAIL") || "";
    const from = Deno.env.get("EMAIL_FROM") || "SkinQuest <orders@skinquestcs.com>";
    const admin = createClient(url, service, { auth: { persistSession: false } });

    const { data: changed, error: refreshError } = await admin.rpc("sq_refresh_expired_trade_locks", { p_limit: 100 });
    if (refreshError) throw refreshError;
    if (!changed?.length) return json({ ok: true, changed: 0, notified: 0 });

    let notified = 0;
    const failures: Array<{ request_id: number; error: string }> = [];

    for (const row of changed) {
      try {
        const { data: order, error: orderError } = await admin
          .from("redemption_requests")
          .select("*")
          .eq("id", row.request_id)
          .single();
        if (orderError || !order) throw orderError || new Error("Order disappeared after refresh.");

        if (!resendKey || !adminEmail) {
          throw new Error("RESEND_API_KEY or ADMIN_REWARD_EMAIL is not configured.");
        }

        const { data: profile } = await admin
          .from("profiles")
          .select("contact_email,contact_email_verified_at")
          .eq("id", order.user_id)
          .maybeSingle();
        const { data: authUser } = await admin.auth.admin.getUserById(order.user_id);
        const authEmail = String(authUser?.user?.email || "").trim().toLowerCase();
        const contactEmail = profile?.contact_email_verified_at
          ? String(profile?.contact_email || "").trim().toLowerCase()
          : "";
        const userEmail = contactEmail || (authEmail && !authEmail.endsWith("@steam.skinquestcs.com") ? authEmail : "");
        const orderNumber = order.order_number || `SQ-R-${String(order.id).padStart(6, "0")}`;
        const dashboard = `https://skinquestcs.com/dashboard?request=${encodeURIComponent(String(order.id))}`;
        const adminUrl = `https://skinquestcs.com/admin?order=${encodeURIComponent(String(order.id))}`;

        const send = async (to: string, subject: string, html: string) => {
          const response = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
            body: JSON.stringify({ from, to: [to], subject, html }),
          });
          if (!response.ok) throw new Error(`Resend returned ${response.status}`);
        };

        const jobs: Array<{ target: "admin_ready" | "user"; promise: Promise<void> }> = [{
          target: "admin_ready",
          promise: send(
            adminEmail,
            `READY TO TRADE ${orderNumber}: ${order.reward_name}`,
            `<h1>Reward ready to trade</h1><p><strong>${esc(orderNumber)}</strong> — ${esc(order.reward_name)}</p><p>The Steam trade lock has ended automatically. Send the customer trade offer.</p><p><a href="${adminUrl}">Open order in admin</a></p>`,
          ),
        }];
        if (userEmail) jobs.push({
          target: "user",
          promise: send(
            userEmail,
            `SkinQuest ${orderNumber}: ready to trade`,
            `<h1>Your reward is ready to trade</h1><p><strong>${esc(order.reward_name)}</strong> is unlocked and ready for SkinQuest to send.</p><p>You do not need to place another order. Keep an eye on your Steam trade offers and your SkinQuest dashboard.</p><p><a href="${dashboard}">View order</a></p>`,
          ),
        });

        const results = await Promise.allSettled(jobs.map((job) => job.promise));
        const now = new Date().toISOString();
        const update: Record<string, unknown> = {};
        const sendFailures: string[] = [];
        results.forEach((result, index) => {
          const target = jobs[index].target;
          if (result.status === "fulfilled") {
            if (target === "admin_ready") update.ready_admin_notified_at = now;
            if (target === "user") {
              update.last_user_notified_status = "ready_to_trade";
              update.user_status_notified_at = now;
            }
          } else {
            sendFailures.push(`${target}: ${result.reason instanceof Error ? result.reason.message : "send failed"}`);
          }
        });
        if (!userEmail) {
          update.last_user_notified_status = "ready_to_trade";
          update.user_status_notified_at = now;
        }
        const userDone = !userEmail || update.last_user_notified_status === "ready_to_trade";
        const adminDone = Boolean(update.ready_admin_notified_at);
        if (userDone && adminDone) {
          update.last_notified_status = "ready_to_trade";
          update.status_notified_at = now;
        }
        if (Object.keys(update).length) await admin.from("redemption_requests").update(update).eq("id", order.id).eq("status", "ready_to_trade");
        if (sendFailures.length) throw new Error(sendFailures.join("; "));
        notified += 1;
      } catch (error) {
        failures.push({
          request_id: Number(row.request_id),
          error: error instanceof Error ? error.message : "Notification failed.",
        });
      }
    }

    return json({ ok: failures.length === 0, changed: changed.length, notified, failures }, failures.length ? 207 : 200);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unexpected sweep error." }, 500);
  }
});
