import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import md5 from "npm:blueimp-md5@2.19.0";
const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function reply(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!["GET", "POST"].includes(req.method)) return reply({ error: "Method not allowed." },405);
  const url = Deno.env.get("SUPABASE_URL")!;
  const client = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: {
      headers: { Authorization: req.headers.get("Authorization") || "" },
    },
  });
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) return reply({ error: "Authentication required." }, 401);

  const appIdValue = (Deno.env.get("CPX_APP_ID") || "33831").trim();
  const appId = Number(appIdValue);
  const secret = Deno.env.get("CPX_SECURE_HASH_SECRET") || "";
  const cpxReady = Number.isInteger(appId) && appId>0 && !!secret;

  // CPX requires md5(ext_user_id + "-" + secure_hash_secret). Only the
  // derived per-user hash is returned; the publisher secret stays server-side.
  const secureHash = cpxReady ? md5(`${user.id}-${secret}`) : "";
  const wallUrl = new URL("https://offers.cpx-research.com/index.php");
  wallUrl.searchParams.set("app_id", String(appId));
  wallUrl.searchParams.set("ext_user_id", user.id);
  wallUrl.searchParams.set("secure_hash", secureHash);

  // Configure the real TimeWall placement URL only after the placement exists.
  // The {user_id} placeholder must bind each wall visit to this authenticated
  // SkinQuest account; do not expose a generic wall URL without user binding.
  let timewallUrl: string | null = null;
  const template = Deno.env.get("TIMEWALL_IFRAME_URL_TEMPLATE") ||
    "https://timewall.io/users/login?oid=cbade60b064c1284&uid={user_id}";
  if (template && template.split("{user_id}").length === 2) {
    try {
      const prepared = new URL(template.replace("{user_id}", encodeURIComponent(user.id)));
      if (prepared.protocol === "https:" && prepared.hostname === "timewall.io" &&
          prepared.searchParams.get("uid")===user.id && prepared.searchParams.get("oid"))
        timewallUrl = prepared.toString();
    } catch { /* Unconfigured TimeWall must never interrupt CPX. */ }
  }

  // Earn needs a separate placement, not the surveys-only placement above.
  let timewallEarnUrl: string | null = null;
  const earnTemplate = Deno.env.get("TIMEWALL_EARN_URL_TEMPLATE") || "";
  if (Deno.env.get("TIMEWALL_EARN_SECRET_KEY") && earnTemplate.split("{user_id}").length === 2) {
    try {
      const prepared = new URL(earnTemplate.replace("{user_id}", encodeURIComponent(user.id)));
      const surveyOid = timewallUrl ? new URL(timewallUrl).searchParams.get("oid") : null;
      if (prepared.protocol === "https:" && prepared.hostname === "timewall.io" &&
          prepared.searchParams.get("uid") === user.id && prepared.searchParams.get("oid") &&
          prepared.searchParams.get("oid") !== surveyOid) timewallEarnUrl = prepared.toString();
    } catch { /* Not configured: Earn stays a labelled preview. */ }
  }
  return reply({
    wall_url: cpxReady ? wallUrl.toString() : null,
    cpx_error: cpxReady ? null : "CPX credentials are not configured.",
    timewall_wall_url: timewallUrl,
    timewall_earn_url: timewallEarnUrl,
    cpx_widget: cpxReady ? {
      app_id: appId,
      ext_user_id: user.id,
      secure_hash: secureHash,
    } : null,
  });
});
