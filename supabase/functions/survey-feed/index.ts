import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import md5 from "npm:blueimp-md5@2.19.0";
const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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
  if (!Number.isInteger(appId) || appId <= 0) {
    return reply({ error: "CPX_APP_ID is not configured correctly." }, 503);
  }
  if (!secret) {
    return reply({ error: "CPX_SECURE_HASH_SECRET is not configured." }, 503);
  }

  // CPX requires md5(ext_user_id + "-" + secure_hash_secret). Only the
  // derived per-user hash is returned; the publisher secret stays server-side.
  const secureHash = md5(`${user.id}-${secret}`);
  const wallUrl = new URL("https://offers.cpx-research.com/index.php");
  wallUrl.searchParams.set("app_id", String(appId));
  wallUrl.searchParams.set("ext_user_id", user.id);
  wallUrl.searchParams.set("secure_hash", secureHash);

  return reply({
    wall_url: wallUrl.toString(),
    cpx_widget: {
      app_id: appId,
      ext_user_id: user.id,
      secure_hash: secureHash,
    },
  });
});
