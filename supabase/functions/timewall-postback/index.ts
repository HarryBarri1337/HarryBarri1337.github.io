import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});

async function digestHex(input: string) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function compareHex(received: string, expected: string) {
  if (!/^[a-f0-9]{64}$/i.test(received)) return false;
  let difference = 0;
  for (let i = 0; i < 64; i++) difference |= received.toLowerCase().charCodeAt(i) ^ expected.charCodeAt(i);
  return difference === 0;
}

// TimeWall's documented hash uses SHA256(userID + rawRevenue + secretKey).
// The transaction ID is not covered by that hash: the owner must reconcile
// event totals with the TimeWall dashboard before fulfilling Steam trades.
Deno.serve(async (request) => {
  if (request.method !== "GET") return reply({ error: "GET required." }, 405);
  const secret = Deno.env.get("TIMEWALL_SECRET_KEY") || "";
  const coinsPerUsd = Number(Deno.env.get("TIMEWALL_COINS_PER_USD") || "");
  if (!secret || !Number.isInteger(coinsPerUsd) || coinsPerUsd < 1 || coinsPerUsd > 100000)
    return reply({ error: "TimeWall not configured." }, 503);

  const query = new URL(request.url).searchParams;
  const userId = query.get("userid") || "";
  const eventId = query.get("txid") || "";
  const revenue = query.get("revenue") || "";
  const hash = query.get("hash") || "";
  const type = (query.get("type") || "").toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId) ||
      !eventId || eventId.length > 180 || !/^-?(?:0|[1-9]\d{0,5})(?:\.\d{1,6})?$/.test(revenue) ||
      !["credit", "hold", "hold_cancelled", "chargeback"].includes(type))
    return reply({ error: "Invalid event fields." }, 400);
  if (!compareHex(hash, await digestHex(userId + revenue + secret)))
    return reply({ error: "Invalid postback hash." }, 401);

  // Holds and released holds are NOT verified earnings. A chargeback must
  // reverse the original credit event, not create a new negative-credit ID.
  if (type === "hold" || type === "hold_cancelled")
    return reply({ ok: true, status: "ignored_hold" });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  if (type === "chargeback") {
    const original = query.get("original_txid") || "";
    if (!original || original.length > 180)
      return reply({ error: "Missing original transaction ID." }, 400);
    const { data, error } = await admin.rpc("sq_reverse_timewall_postback", {
      p_original_txid: original, p_user_id: userId,
    });
    if (error) {
      console.error("TimeWall chargeback rejected:", error.message);
      return reply({ error: "Chargeback could not be applied." }, 500);
    }
    return reply(data);
  }

  // Do not trust currencyAmount from the URL; convert only hashed revenue.
  const coins = Math.round(Number(revenue) * coinsPerUsd);
  if (!Number.isInteger(coins) || coins < 1 || coins > 5000)
    return reply({ error: "Event exceeds credit limit." }, 400);

  const { data, error } = await admin.rpc("sq_process_timewall_postback", {
    p_event_id: eventId, p_user_id: userId, p_amount: coins, p_revenue: revenue,
  });
  if (error) {
    console.error("TimeWall postback rejected:", error.message);
    return reply({ error: "Event could not be credited." }, 500);
  }
  return reply(data);
});
