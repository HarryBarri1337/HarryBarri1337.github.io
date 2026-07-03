SkinQuest v11.9.2 Steam Connect setup

Status before this hotfix:
- Steam Connect works.
- The Steam login page may show the Supabase functions domain because steam-auth-start used Supabase as the OpenID realm.

What v11.9.2 changes:
- Adds steam-callback.html to the website.
- steam-auth-start should now use:
  - openid.realm = https://skinquestcs.com
  - openid.return_to = https://skinquestcs.com/steam-callback.html?state=...

SQL:
- No new SQL is needed if v11.9.1 Steam SQL was already run.
- The included upgrade SQL is intentionally no-op.

Required Supabase action:
Replace supabase/functions/steam-auth-start/index.ts with this version and deploy it:

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function randomState() {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const siteUrl = Deno.env.get("SITE_URL") || "https://skinquestcs.com";

    const authHeader = req.headers.get("Authorization");

    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing auth header" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Not logged in" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const state = randomState();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    await adminClient
      .from("steam_auth_states")
      .delete()
      .eq("user_id", user.id);

    const { error: insertError } = await adminClient
      .from("steam_auth_states")
      .insert({
        state,
        user_id: user.id,
        expires_at: expiresAt,
      });

    if (insertError) {
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const cleanSiteUrl = siteUrl.replace(/\/$/, "");
    const callbackUrl = `${cleanSiteUrl}/steam-callback.html`;

    const params = new URLSearchParams({
      "openid.ns": "http://specs.openid.net/auth/2.0",
      "openid.mode": "checkid_setup",
      "openid.return_to": `${callbackUrl}?state=${state}`,
      "openid.realm": cleanSiteUrl,
      "openid.identity": "http://specs.openid.net/auth/2.0/identifier_select",
      "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
    });

    const steamUrl = `https://steamcommunity.com/openid/login?${params.toString()}`;

    return new Response(JSON.stringify({ url: steamUrl }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

Deploy command:
npx.cmd supabase functions deploy steam-auth-start --no-verify-jwt

After deploying:
1. Upload/push the v11.9.2 frontend files.
2. Log in to SkinQuest.
3. Settings > Connect Steam.
4. Steam should show skinquestcs.com.
5. After signing in, it should return to Settings and show Steam connected.
