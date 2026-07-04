import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

async function fetchSteamProfile(steamId: string) {
  try {
    const res = await fetch(`https://steamcommunity.com/profiles/${steamId}/?xml=1`);
    const xml = await res.text();
    const name = xml.match(/<steamID><!\[CDATA\[(.*?)\]\]><\/steamID>/)?.[1]
      || xml.match(/<steamID>(.*?)<\/steamID>/)?.[1]
      || null;
    const avatar = xml.match(/<avatarFull><!\[CDATA\[(.*?)\]\]><\/avatarFull>/)?.[1]
      || xml.match(/<avatarFull>(.*?)<\/avatarFull>/)?.[1]
      || null;
    return { name, avatar };
  } catch {
    return { name: null, avatar: null };
  }
}

function steamEmail(steamId: string) {
  return `steam_${steamId}@steam.skinquestcs.com`;
}

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const siteUrl = Deno.env.get("SITE_URL") || "https://skinquestcs.com";

    const url = new URL(req.url);
    const state = url.searchParams.get("state");
    if (!state) return Response.redirect(`${siteUrl}/settings.html?steam=missing_state`, 302);

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: stateRow, error: stateError } = await adminClient
      .from("steam_auth_states")
      .select("state,user_id,mode,expires_at")
      .eq("state", state)
      .maybeSingle();

    if (stateError || !stateRow) return Response.redirect(`${siteUrl}/settings.html?steam=invalid_state`, 302);

    if (new Date(stateRow.expires_at).getTime() < Date.now()) {
      await adminClient.from("steam_auth_states").delete().eq("state", state);
      return Response.redirect(`${siteUrl}/settings.html?steam=expired_state`, 302);
    }

    const verifyParams = new URLSearchParams(url.searchParams);
    verifyParams.set("openid.mode", "check_authentication");

    const verifyRes = await fetch("https://steamcommunity.com/openid/login", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: verifyParams.toString(),
    });

    const verifyText = await verifyRes.text();
    if (!verifyText.includes("is_valid:true")) {
      return Response.redirect(`${siteUrl}/settings.html?steam=invalid_login`, 302);
    }

    const claimedId = url.searchParams.get("openid.claimed_id") || "";
    const steamId = (claimedId.match(/\/id\/(\d+)$/) || claimedId.match(/\/profiles\/(\d+)$/))?.[1];

    if (!steamId) {
      return Response.redirect(`${siteUrl}/settings.html?steam=no_steam_id`, 302);
    }

    const steamProfile = await fetchSteamProfile(steamId);
    const mode = stateRow.mode || "connect";

    if (mode === "connect") {
      if (!stateRow.user_id) {
        return Response.redirect(`${siteUrl}/settings.html?steam=invalid_state`, 302);
      }

      const { error: updateError } = await adminClient
        .from("profiles")
        .update({
          steam_id: steamId,
          steam_name: steamProfile.name,
          steam_avatar_url: steamProfile.avatar,
          steam_connected_at: new Date().toISOString(),
        })
        .eq("id", stateRow.user_id);

      await adminClient.from("steam_auth_states").delete().eq("state", state);

      if (updateError) {
        return Response.redirect(`${siteUrl}/settings.html?steam=save_failed`, 302);
      }

      return Response.redirect(`${siteUrl}/settings.html?steam=connected`, 302);
    }

    let userId: string | null = null;
    let email = steamEmail(steamId);

    const { data: existingProfile } = await adminClient
      .from("profiles")
      .select("id")
      .eq("steam_id", steamId)
      .maybeSingle();

    if (existingProfile?.id) {
      userId = existingProfile.id;

      const { data: authUser } = await adminClient.auth.admin.getUserById(userId);
      email = authUser?.user?.email || email;
    } else {
      const { data: created, error: createError } = await adminClient.auth.admin.createUser({
        email,
        email_confirm: true,
        user_metadata: {
          provider: "steam",
          steam_id: steamId,
          steam_name: steamProfile.name,
          steam_avatar_url: steamProfile.avatar,
        },
      });

      if (createError && !String(createError.message || "").toLowerCase().includes("already")) {
        await adminClient.from("steam_auth_states").delete().eq("state", state);
        return Response.redirect(`${siteUrl}/auth-confirm.html?steam=login&error=steam_create_failed`, 302);
      }

      if (created?.user?.id) {
        userId = created.user.id;
      } else {
        const { data: bySteamEmail, error: linkProbeError } = await adminClient.auth.admin.generateLink({
          type: "magiclink",
          email,
          options: { redirectTo: `${siteUrl}/auth-confirm.html?steam=login` },
        });

        if (linkProbeError || !bySteamEmail) {
          await adminClient.from("steam_auth_states").delete().eq("state", state);
          return Response.redirect(`${siteUrl}/auth-confirm.html?steam=login&error=steam_user_lookup_failed`, 302);
        }
      }

      if (userId) {
        await adminClient.from("profiles").upsert({
          id: userId,
          username: steamProfile.name || `steam_${steamId}`,
          steam_id: steamId,
          steam_name: steamProfile.name,
          steam_avatar_url: steamProfile.avatar,
          steam_connected_at: new Date().toISOString(),
        }, { onConflict: "id" });
      }
    }

    await adminClient.from("steam_auth_states").delete().eq("state", state);

    const { data: linkData, error: linkError } = await adminClient.auth.admin.generateLink({
      type: "magiclink",
      email,
      options: { redirectTo: `${siteUrl}/auth-confirm.html?steam=login` },
    });

    const actionLink = linkData?.properties?.action_link;

    if (linkError || !actionLink) {
      return Response.redirect(`${siteUrl}/auth-confirm.html?steam=login&error=magic_link_failed`, 302);
    }

    return Response.redirect(actionLink, 302);
  } catch (err) {
    console.error(err);
    return new Response("Steam auth callback error", { status: 500 });
  }
});