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

function cleanMode(value: unknown) {
  const mode = String(value || "").toLowerCase();
  return mode === "signup" ? "signup" : "login";
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const siteUrl = Deno.env.get("SITE_URL") || "https://skinquestcs.com";

    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch {}

    const authHeader = req.headers.get("Authorization");
    let userId: string | null = null;
    let mode = cleanMode(body.mode);

    if (authHeader) {
      const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: authHeader } },
      });

      const { data: { user } } = await userClient.auth.getUser();
      if (user?.id) {
        userId = user.id;
        mode = "connect";
      }
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const state = randomState();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    if (userId) {
      await adminClient.from("steam_auth_states").delete().eq("user_id", userId);
    }

    const { error: insertError } = await adminClient
      .from("steam_auth_states")
      .insert({ state, user_id: userId, mode, expires_at: expiresAt });

    if (insertError) {
      return new Response(JSON.stringify({ error: insertError.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const callbackUrl = `${siteUrl}/steam-callback.html`;
    const params = new URLSearchParams({
      "openid.ns": "http://specs.openid.net/auth/2.0",
      "openid.mode": "checkid_setup",
      "openid.return_to": `${callbackUrl}?state=${state}`,
      "openid.realm": siteUrl,
      "openid.identity": "http://specs.openid.net/auth/2.0/identifier_select",
      "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
    });

    return new Response(JSON.stringify({ url: `https://steamcommunity.com/openid/login?${params.toString()}` }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});