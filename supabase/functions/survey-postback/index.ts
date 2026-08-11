import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const payload =
      req.method === "POST"
        ? await req.json().catch(() => ({}))
        : Object.fromEntries(url.searchParams);
    const supplied =
      req.headers.get("x-postback-secret") ||
      url.searchParams.get("secret") ||
      payload.secret;
    if (!supplied || supplied !== Deno.env.get("SURVEY_POSTBACK_SECRET"))
      return reply({ error: "Invalid postback secret." }, 401);
    const provider = String(
      payload.provider || url.searchParams.get("provider") || "",
    ).toLowerCase();
    const eventId = String(
      payload.event_id ||
        payload.transaction_id ||
        payload.txid ||
        payload.id ||
        "",
    );
    const userId = String(
      payload.user_id || payload.ext_user_id || payload.uid || "",
    );
    const amount = Math.round(
      Number(payload.coins ?? payload.amount ?? payload.reward ?? 0),
    );
    const rawStatus = String(
      payload.status || payload.state || "completed",
    ).toLowerCase();
    const status = ["reversed", "chargeback", "rejected"].includes(rawStatus)
      ? rawStatus === "rejected"
        ? "rejected"
        : "reversed"
      : rawStatus === "pending"
        ? "pending"
        : "completed";
    if (
      !provider ||
      !eventId ||
      !/^[0-9a-f-]{36}$/i.test(userId) ||
      !Number.isInteger(amount)
    )
      return reply({ error: "Missing or invalid postback fields." }, 400);
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data, error } = await admin.rpc("process_offerwall_postback", {
      p_provider: provider,
      p_event_id: eventId,
      p_user_id: userId,
      p_amount: amount,
      p_status: status,
      p_payload: payload,
    });
    if (error) throw error;
    return reply(data);
  } catch (error) {
    return reply(
      { error: error instanceof Error ? error.message : "Unexpected error." },
      500,
    );
  }
});
