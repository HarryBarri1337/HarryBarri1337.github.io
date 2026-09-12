import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type SteamTag = {
  category?: string;
  internal_name?: string;
  localized_category_name?: string;
  localized_tag_name?: string;
};

type SteamDescription = {
  market_name?: string;
  market_hash_name?: string;
  icon_url?: string;
  icon_url_large?: string;
  type?: string;
  marketable?: number;
  tags?: SteamTag[];
};

type SteamResult = {
  name?: string;
  hash_name?: string;
  sell_price?: number;
  sale_price?: number;
  sell_listings?: number;
  asset_description?: SteamDescription;
};

const ALLOWED_ORIGINS = new Set([
  "https://skinquestcs.com",
  "https://www.skinquestcs.com",
  "http://localhost:8000",
  "http://127.0.0.1:8000",
]);

function responseHeaders(origin: string | null) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Headers"] = "authorization, apikey, content-type, x-steam-sync-secret";
    headers["Access-Control-Allow-Methods"] = "POST, OPTIONS";
  }
  return headers;
}

const json = (body: unknown, status = 200, origin: string | null = null) =>
  new Response(JSON.stringify(body), { status, headers: responseHeaders(origin) });

function safeSecretEqual(left: string, right: string) {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) difference |= a[index] ^ b[index];
  return difference === 0;
}

function text(value: unknown, max = 500) {
  return String(value ?? "").trim().slice(0, max);
}

function tagValue(description: SteamDescription, category: string) {
  const tag = (description.tags || []).find((item) =>
    text(item.category, 80).toLowerCase() === category.toLowerCase() ||
    text(item.localized_category_name, 80).toLowerCase() === category.toLowerCase()
  );
  return {
    internal: text(tag?.internal_name, 120),
    label: text(tag?.localized_tag_name, 120),
  };
}

function isEligibleReward(description: SteamDescription, marketName: string) {
  if (description.marketable === 0 || !marketName) return false;
  if (/^(sticker|patch|graffiti|sealed graffiti|music kit|stattrak™ music kit|charm|agent)\s*\|/i.test(marketName)) return false;

  const type = tagValue(description, "Type");
  const typeText = `${type.internal} ${type.label} ${text(description.type, 160)}`.toLowerCase();
  const supportedType = /(pistol|smg|rifle|sniper|shotgun|machinegun|machine gun|knife|glove|hands|weaponcase|weapon case|container|case)/i.test(typeText);
  const skinName = marketName.includes(" | ") && !/^(sticker|patch|graffiti|music kit|charm|agent)\s*\|/i.test(marketName);
  const caseName = /(?:case|weapon case)$/i.test(marketName);
  return supportedType || skinName || caseName;
}

function rarityKey(description: SteamDescription) {
  const rarity = tagValue(description, "Rarity");
  const value = `${rarity.internal} ${rarity.label}`.toLowerCase();
  if (value.includes("contraband")) return "contraband";
  if (value.includes("covert") || value.includes("ancient")) return "covert";
  if (value.includes("classified") || value.includes("legendary")) return "classified";
  if (value.includes("restricted") || value.includes("mythical")) return "restricted";
  if (value.includes("mil-spec") || value.includes("milspec") || value.includes("rare")) return "milspec";
  if (value.includes("industrial") || value.includes("uncommon")) return "industrial";
  if (value.includes("consumer") || value.includes("common")) return "consumer";
  return null;
}

function conditionCode(description: SteamDescription, marketName: string) {
  const exterior = tagValue(description, "Exterior").label || marketName.match(/\(([^()]+)\)\s*$/)?.[1] || "";
  const value = exterior.toLowerCase();
  if (value.includes("factory new")) return "FN";
  if (value.includes("minimal wear")) return "MW";
  if (value.includes("field-tested") || value.includes("field tested")) return "FT";
  if (value.includes("well-worn") || value.includes("well worn")) return "WW";
  if (value.includes("battle-scarred") || value.includes("battle scarred")) return "BS";
  return exterior ? exterior.slice(0, 40) : null;
}

function imageUrl(description: SteamDescription) {
  const icon = text(description.icon_url_large || description.icon_url, 420);
  if (!icon || !/^[A-Za-z0-9_./-]+$/.test(icon)) return null;
  return `https://community.cloudflare.steamstatic.com/economy/image/${icon}/360fx360f`;
}

function normalizeResult(result: SteamResult) {
  const description = result.asset_description || {};
  const marketName = text(description.market_hash_name || result.hash_name || description.market_name || result.name, 240);
  const price = Math.trunc(Number(result.sell_price ?? result.sale_price ?? 0));
  if (!Number.isSafeInteger(price) || price <= 0 || !isEligibleReward(description, marketName)) return null;
  return {
    market_name: marketName,
    image_url: imageUrl(description),
    description: text(description.type, 500) || null,
    rarity: rarityKey(description),
    condition: conditionCode(description, marketName),
    steam_price_minor: price,
    steam_listing_count: Math.max(0, Math.trunc(Number(result.sell_listings || 0))),
  };
}

async function pause(milliseconds: number) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function fetchSteamPage(start: number, count: number) {
  const url = new URL("https://steamcommunity.com/market/search/render/");
  url.searchParams.set("query", "");
  url.searchParams.set("start", String(start));
  url.searchParams.set("count", String(count));
  url.searchParams.set("search_descriptions", "0");
  url.searchParams.set("sort_column", "name");
  url.searchParams.set("sort_dir", "asc");
  url.searchParams.set("appid", "730");
  url.searchParams.set("norender", "1");
  url.searchParams.set("currency", "3");
  url.searchParams.set("l", "english");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 18_000);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        "Accept": "application/json,text/plain;q=0.9,*/*;q=0.5",
        "User-Agent": "SkinQuest/14.5.0 reward-price-sync (support@skinquestcs.com)",
      },
    });
    if (response.status === 429) throw new Error("Steam rate limited the catalog request. Wait before retrying; the saved cursor was preserved.");
    if (!response.ok) throw new Error(`Steam catalog returned HTTP ${response.status}.`);
    const payload = await response.json();
    if (![true, 1].includes(payload?.success) || !Array.isArray(payload?.results)) throw new Error("Steam returned an invalid catalog response.");
    return payload as { success: boolean; start?: number; pagesize?: number; total_count?: number; results: SteamResult[] };
  } finally {
    clearTimeout(timeout);
  }
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: responseHeaders(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405, origin);
  if (origin && !ALLOWED_ORIGINS.has(origin)) return json({ error: "Origin not allowed." }, 403, origin);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!supabaseUrl || !serviceKey) return json({ error: "Server configuration is incomplete." }, 500, origin);
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  try {
    const cronSecret = Deno.env.get("STEAM_MARKET_SYNC_SECRET") || "";
    const suppliedSecret = req.headers.get("x-steam-sync-secret") || "";
    const cronAuthorized = Boolean(cronSecret && suppliedSecret && safeSecretEqual(cronSecret, suppliedSecret));
    let ownerAuthorized = false;

    if (!cronAuthorized) {
      const authorization = req.headers.get("authorization") || "";
      const token = authorization.replace(/^Bearer\s+/i, "").trim();
      if (token) {
        const { data: userResult, error: userError } = await admin.auth.getUser(token);
        if (!userError && userResult?.user?.id) {
          const { data: role } = await admin.from("admin_users").select("role").eq("user_id", userResult.user.id).maybeSingle();
          ownerAuthorized = role?.role === "owner";
        }
      }
    }

    if (!cronAuthorized && !ownerAuthorized) return json({ error: "Owner or scheduler authorization required." }, 401, origin);

    let body: Record<string, unknown> = {};
    try { body = await req.json(); } catch { body = {}; }
    if (text(body.action, 20).toLowerCase() !== "catalog") return json({ error: "Unsupported sync action." }, 400, origin);

    const { data: syncState, error: stateError } = await admin
      .from("sq_steam_catalog_sync_state")
      .select("next_start")
      .eq("id", 1)
      .maybeSingle();
    if (stateError) throw stateError;

    const requestedStart = Number(body.start);
    let cursor = body.reset === true
      ? 0
      : Number.isInteger(requestedStart) && requestedStart >= 0
        ? requestedStart
        : Math.max(0, Number(syncState?.next_start || 0));
    const initialStart = cursor;
    const maxPages = Math.max(1, Math.min(8, Math.trunc(Number(body.max_pages || 3))));
    const pageSize = 100;
    let totalCount = 0;
    let scanned = 0;
    let completed = false;
    const items = new Map<string, NonNullable<ReturnType<typeof normalizeResult>>>();

    for (let page = 0; page < maxPages; page += 1) {
      const payload = await fetchSteamPage(cursor, pageSize);
      const results = payload.results || [];
      totalCount = Math.max(0, Math.trunc(Number(payload.total_count || totalCount || 0)));
      scanned += results.length;
      for (const raw of results) {
        const item = normalizeResult(raw);
        if (item) items.set(item.market_name.toLowerCase(), item);
      }

      const returnedPageSize = Math.max(1, Math.trunc(Number(payload.pagesize || results.length || pageSize)));
      cursor += returnedPageSize;
      completed = totalCount > 0 && cursor >= totalCount;
      if (completed) break;
      if (!results.length) throw new Error("Steam returned an empty page before the catalog ended. The cursor was preserved.");
      if (page + 1 < maxPages) await pause(900);
    }

    const catalogItems = Array.from(items.values());
    const { data: applied, error: applyError } = await admin.rpc("sq_service_apply_steam_catalog_batch", {
      p_items: catalogItems,
      p_start: initialStart,
      p_next_start: cursor,
      p_total_count: totalCount,
      p_results_scanned: scanned,
      p_completed: completed,
    });
    if (applyError) throw applyError;

    return json({
      ok: true,
      scanned,
      eligible: catalogItems.length,
      created: Number(applied?.created || 0),
      updated: Number(applied?.updated || 0),
      next_start: Number(applied?.next_start || 0),
      total_count: Number(applied?.total_count || totalCount),
      completed: Boolean(applied?.completed),
    }, 200, origin);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected Steam catalog sync error.";
    try { await admin.rpc("sq_service_record_steam_sync_error", { p_error: message }); } catch {}
    return json({ error: message }, 500, origin);
  }
});
