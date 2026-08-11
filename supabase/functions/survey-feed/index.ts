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
  const surveys: Array<Record<string, unknown>> = [
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
  const bitlabsToken = Deno.env.get("BITLABS_API_TOKEN") || "";
  const bitlabsWallUrl = bitlabsToken
    ? `https://web.bitlabs.ai/?uid=${encodeURIComponent(user.id)}&token=${encodeURIComponent(bitlabsToken)}&theme=DARK&display_mode=surveys&sdk=TAB`
    : "";

  if (bitlabsWallUrl) {
    surveys.push({
      provider: "BitLabs",
      title: "Available BitLabs surveys",
      description:
        "Open the live BitLabs list for surveys matched to your location and device.",
      coins: 0,
      minutes: 0,
      url: bitlabsWallUrl,
    });
  }

  // BitLabs must enable publisher backend Survey API access before this flag is
  // switched on. Until then the signed-in offerwall above remains fully usable.
  if (bitlabsToken && Deno.env.get("BITLABS_BACKEND_API_ENABLED") === "true") {
    try {
      const feedUrl = new URL("https://api.bitlabs.ai/v2/client/surveys");
      const clientIp = (req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || "")
        .split(",")[0].trim();
      const userAgent = req.headers.get("user-agent") || "";
      if (clientIp) feedUrl.searchParams.set("client_ip", clientIp);
      if (userAgent) feedUrl.searchParams.set("client_useragent", userAgent);
      const feedResponse = await fetch(feedUrl, {
        headers: { "X-Api-Token": bitlabsToken, "X-User-Id": user.id },
      });
      if (feedResponse.ok) {
        const feed = await feedResponse.json();
        const available = Array.isArray(feed?.data?.surveys) ? feed.data.surveys : [];
        const mapped = available.slice(0, 6).map((survey: Record<string, unknown>) => {
          const category = survey.category && typeof survey.category === "object"
            ? survey.category as Record<string, unknown>
            : {};
          return {
            provider: "BitLabs",
            title: String(category.name || "Recommended BitLabs survey"),
            description: "Reward and availability are confirmed by BitLabs when you open the survey.",
            coins: Math.max(0, Math.round(Number(survey.value || 0))),
            minutes: Math.max(0, Math.round(Number(survey.loi || 0))),
            url: String(survey.click_url || bitlabsWallUrl),
          };
        });
        surveys.unshift(...mapped);
      } else {
        console.warn("BitLabs Survey API returned", feedResponse.status);
      }
    } catch (error) {
      console.warn("BitLabs Survey API unavailable", error);
    }
  }

  return new Response(JSON.stringify({ wall_url: wallUrl, bitlabs_wall_url: bitlabsWallUrl, surveys }), {
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
});
