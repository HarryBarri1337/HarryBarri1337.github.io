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
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json();
    if (body?.confirmation !== "DELETE")
      return reply({ error: "Confirmation is required." }, 400);
    const url = Deno.env.get("SUPABASE_URL")!;
    const auth = req.headers.get("Authorization") || "";
    const client = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: auth } },
    });
    const {
      data: { user },
      error,
    } = await client.auth.getUser();
    if (error || !user)
      return reply({ error: "Authentication required." }, 401);
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { count } = await admin
      .from("redemption_requests")
      .select("id", { head: true, count: "exact" })
      .eq("user_id", user.id)
      .in("status", ["pending", "reviewing", "trade_sent"]);
    if ((count || 0) > 0)
      return reply(
        {
          error: "Resolve pending reward requests before deleting the account.",
        },
        409,
      );

    const bitlabsS2s = Deno.env.get("BITLABS_S2S_TOKEN") || "";
    if (bitlabsS2s) {
      const providerDelete = await fetch(
        `https://api.bitlabs.ai/v1/publishers/users/${encodeURIComponent(user.id)}`,
        { method: "DELETE", headers: { "X-S2S-Token": bitlabsS2s } },
      );
      if (!providerDelete.ok && providerDelete.status !== 404) {
        console.error("BitLabs user deletion failed", providerDelete.status, await providerDelete.text());
        return reply(
          { error: "The connected survey data could not be deleted. Please try again." },
          502,
        );
      }
    }
    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) throw deleteError;
    return reply({ ok: true });
  } catch (error) {
    return reply(
      { error: error instanceof Error ? error.message : "Unexpected error." },
      500,
    );
  }
});
