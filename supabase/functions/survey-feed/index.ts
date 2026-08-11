import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import md5 from "npm:blueimp-md5@2.19.0";
const cors = {
  "Access-Control-Allow-Origin": "https://skinquestcs.com",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
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
  if (!user)
    return new Response(JSON.stringify({ error: "Authentication required." }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  const appId = Deno.env.get("CPX_APP_ID") || "33831";
  const secret = Deno.env.get("CPX_SECURE_HASH_SECRET") || "";
  const secureHash = secret
    ? `&secure_hash=${md5(`${user.id}-${secret}`)}`
    : "";
  const wallUrl = `https://offers.cpx-research.com/index.php?app_id=${encodeURIComponent(appId)}&ext_user_id=${encodeURIComponent(user.id)}${secureHash}`;
  const surveys = [
    {
      provider: "CPX",
      title: "Available CPX surveys",
      description:
        "Open the live provider list for surveys matched to your country and device.",
      coins: 0,
      minutes: 0,
      url: wallUrl,
    },
  ];
  return new Response(JSON.stringify({ wall_url: wallUrl, surveys }), {
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
});
