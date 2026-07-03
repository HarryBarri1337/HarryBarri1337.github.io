import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const siteUrl = Deno.env.get("SITE_URL") || "https://skinquestcs.com";

    const url = new URL(req.url);
    const state = url.searchParams.get("state");

    if (!state) {
      return Response.redirect(`${siteUrl}/settings.html?steam=missing_state`, 302);
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: stateRow, error: stateError } = await adminClient
      .from("steam_auth_states")
      .select("state,user_id,expires_at")
      .eq("state", state)
      .maybeSingle();

    if (stateError || !stateRow) {
      return Response.redirect(`${siteUrl}/settings.html?steam=invalid_state`, 302);
    }

    if (new Date(stateRow.expires_at).getTime() < Date.now()) {
      await adminClient.from("steam_auth_states").delete().eq("state", state);
      return Response.redirect(`${siteUrl}/settings.html?steam=expired_state`, 302);
    }

    const verifyParams = new URLSearchParams(url.searchParams);
    verifyParams.set("openid.mode", "check_authentication");

    const verifyRes = await fetch("https://steamcommunity.com/openid/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: verifyParams.toString(),
    });

    const verifyText = await verifyRes.text();

    if (!verifyText.includes("is_valid:true")) {
      return Response.redirect(`${siteUrl}/settings.html?steam=invalid_login`, 302);
    }

    const claimedId = url.searchParams.get("openid.claimed_id") || "";
    const steamIdMatch = claimedId.match(/\/id\/(\d+)$/) || claimedId.match(/\/profiles\/(\d+)$/);
    const steamId = steamIdMatch?.[1];

    if (!steamId) {
      return Response.redirect(`${siteUrl}/settings.html?steam=no_steam_id`, 302);
    }

    const { error: updateError } = await adminClient
      .from("profiles")
      .update({
        steam_id: steamId,
        steam_connected_at: new Date().toISOString(),
      })
      .eq("id", stateRow.user_id);

    await adminClient.from("steam_auth_states").delete().eq("state", state);

    if (updateError) {
      return Response.redirect(`${siteUrl}/settings.html?steam=save_failed`, 302);
    }

    return Response.redirect(`${siteUrl}/settings.html?steam=connected`, 302);
  } catch (err) {
    console.error(err);
    return new Response("Steam auth callback error", { status: 500 });
  }
});