// SkinQuest v11.2 - account settings, support widget cleanup, SQL hardening.

const SUPABASE_URL = "https://ubvkupqgigfxehprsoit.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVidmt1cHFnaWdmeGVocHJzb2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4Nzc4NjIsImV4cCI6MjA5NzQ1Mzg2Mn0.GWI920G80kZYIOiFPvkHr-blpOvY_N-zvDY1QATCjfY";
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const ADMIN_EMAILS = []; // v11.2: admin access must come from Supabase admin_users via is_admin().
const CPX_APP_ID = 33831;
const SUPPORT_EMAIL = ""; // Optional mailto fallback. Supabase support_requests is used first for signed-in users.

let rewardItems = [];
let adminRewardItems = [];
let currentUser = null;
let currentProfile = null;
let currentIsAdmin = false;

function qs(selector) {
  return document.querySelector(selector);
}

function qsa(selector) {
  return Array.from(document.querySelectorAll(selector));
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatDate(value) {
  if (!value) return "Unknown date";
  return new Date(value).toLocaleString();
}

function coinIcon(extraClass = "") {
  const cls = extraClass ? `coin-icon ${extraClass}` : "coin-icon";
  return `<img class="${cls}" src="assets/interface/coin_logo.png" alt="" loading="lazy" onerror="this.style.display='none'" />`;
}

function userInitial(user) {
  const source = user?.email || "S";
  return source.trim().charAt(0).toUpperCase() || "S";
}

function shortEmail(email) {
  if (!email) return "Account";
  const [name, domain] = String(email).split("@");
  if (!domain) return email;
  return `${name}@${domain}`;
}

function getPageUrl(fileName = "index.html") {
  const basePath = location.pathname.replace(/[^/]*$/, "");
  return `${location.origin}${basePath}${fileName}`;
}

function getToastStack() {
  let stack = qs("#toastStack");
  if (!stack) {
    stack = document.createElement("div");
    stack.id = "toastStack";
    stack.className = "toast-stack";
    document.body.appendChild(stack);
  }
  return stack;
}

function showMessage(message, type = "info") {
  const stack = getToastStack();
  const toast = document.createElement("div");
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `
    <div class="toast-dot"></div>
    <p>${escapeHtml(message)}</p>
    <button type="button" aria-label="Close message">×</button>
  `;
  stack.appendChild(toast);
  requestAnimationFrame(() => toast.classList.add("show"));

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    toast.classList.add("leaving");
    setTimeout(() => toast.remove(), 220);
  };

  toast.querySelector("button")?.addEventListener("click", close);
  setTimeout(close, Math.max(3600, Math.min(9500, String(message || "").length * 60)));
}

function showConfirm(message, options = {}) {
  return new Promise((resolve) => {
    const backdrop = document.createElement("div");
    backdrop.className = "confirm-backdrop";
    backdrop.innerHTML = `
      <div class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirmTitle">
        <div class="confirm-icon ${options.danger ? "danger" : ""}">${options.icon || "SQ"}</div>
        <div class="confirm-copy">
          <h2 id="confirmTitle">${escapeHtml(options.title || "Confirm action")}</h2>
          <p>${escapeHtml(message)}</p>
        </div>
        <div class="confirm-actions">
          <button class="button button-ghost" type="button" data-confirm-cancel>${escapeHtml(options.cancelText || "Cancel")}</button>
          <button class="button ${options.danger ? "button-danger" : "button-primary"}" type="button" data-confirm-ok>${escapeHtml(options.confirmText || "Confirm")}</button>
        </div>
      </div>
    `;

    let finished = false;
    const done = (value) => {
      if (finished) return;
      finished = true;
      backdrop.classList.remove("show");
      backdrop.classList.add("leaving");
      setTimeout(() => backdrop.remove(), 220);
      resolve(value);
    };

    backdrop.addEventListener("click", (event) => {
      if (event.target === backdrop) done(false);
    });
    document.addEventListener("keydown", function onKey(event) {
      if (!document.body.contains(backdrop)) return document.removeEventListener("keydown", onKey);
      if (event.key === "Escape") done(false);
    });
    backdrop.querySelector("[data-confirm-cancel]")?.addEventListener("click", () => done(false));
    backdrop.querySelector("[data-confirm-ok]")?.addEventListener("click", () => done(true));
    document.body.appendChild(backdrop);
    requestAnimationFrame(() => backdrop.classList.add("show"));
    setTimeout(() => backdrop.querySelector("[data-confirm-ok]")?.focus(), 80);
  });
}

function finishPageLoad() {
  const loader = qs("#pageLoader");
  if (!loader) return;
  loader.classList.add("done");
}

async function getSessionUser() {
  const { data, error } = await sb.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}

function isAdmin(user) {
  return !!user?.id && !!currentIsAdmin;
}

async function fetchAdminStatus(user) {
  if (!user?.id) return false;
  try {
    const { data, error } = await sb.rpc("is_admin");
    if (!error && typeof data === "boolean") return data;
  } catch (error) {
    console.warn("Admin status check failed:", error);
  }

  return false;
}

async function requireUser() {
  const user = await getSessionUser();
  if (!user) throw new Error("You need to sign in first.");
  return user;
}

async function ensureProfile(user) {
  if (!user?.id) throw new Error("You need to sign in first.");

  const { data: existing, error: selectError } = await sb
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  if (!selectError && existing) return existing;

  // Fallback: lets normal users get a profile even if direct insert RLS is too strict.
  const { data: rpcProfile, error: rpcError } = await sb.rpc("ensure_skinquest_profile");
  if (!rpcError && rpcProfile) {
    return Array.isArray(rpcProfile) ? rpcProfile[0] : rpcProfile;
  }

  const username = user.email ? user.email.split("@")[0] : "user";

  const { data: created, error: insertError } = await sb
    .from("profiles")
    .insert({ id: user.id, username })
    .select("*")
    .single();

  if (insertError) {
    const details = rpcError ? ` RPC fallback also failed: ${rpcError.message}` : "";
    throw new Error(`${insertError.message}${details}`);
  }
  return created;
}

async function getTotalEarned(userId) {
  const { data, error } = await sb
    .from("coin_adjustments")
    .select("amount, reason")
    .eq("user_id", userId);

  if (error || !data) return 0;
  return data
    .filter((row) => Number(row.amount) > 0 && !String(row.reason || "").toLowerCase().startsWith("level reward"))
    .reduce((sum, row) => sum + Number(row.amount || 0), 0);
}

async function claimLevelRewards() {
  const { data, error } = await sb.rpc("claim_level_rewards");
  if (error) throw error;
  return data || null;
}

const COINS_PER_LEVEL = 1000;
const LEVEL_BONUS_COINS = 50;

function calculateLevel(totalEarned) {
  return Math.max(1, Math.floor(Number(totalEarned || 0) / COINS_PER_LEVEL) + 1);
}

function coinsForLevel(level) {
  return Math.max(0, level - 1) * COINS_PER_LEVEL;
}

function getLevelProgress(totalEarned) {
  const earned = Number(totalEarned || 0);
  const level = calculateLevel(earned);
  const currentFloor = coinsForLevel(level);
  const nextFloor = coinsForLevel(level + 1);
  const progress = ((earned - currentFloor) / COINS_PER_LEVEL) * 100;
  return { level, currentFloor, nextFloor, progress: Math.max(0, Math.min(100, progress)) };
}

function updateAdminVisibility(user) {
  qsa('a[href="admin.html"]').forEach((link) => {
    link.classList.toggle("hidden-admin-link", !isAdmin(user));
  });
}

function initNav() {
  const toggle = qs("[data-nav-toggle]");
  const nav = qs("[data-nav]");

  const setOpen = (open) => {
    if (!nav || !toggle) return;
    nav.classList.toggle("open", open);
    toggle.classList.toggle("open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", open ? "Close navigation" : "Open navigation");
  };

  if (toggle && nav) {
    toggle.setAttribute("aria-expanded", "false");
    toggle.addEventListener("click", (event) => {
      event.stopPropagation();
      setOpen(!nav.classList.contains("open"));
    });

    nav.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => setOpen(false));
    });

    document.addEventListener("click", (event) => {
      if (!event.target.closest(".site-header")) setOpen(false);
    });

    window.addEventListener("resize", () => {
      if (window.innerWidth > 1080) setOpen(false);
    });
  }

  const current = location.pathname.split("/").pop() || "index.html";
  nav?.querySelectorAll("a").forEach((link) => {
    if (link.getAttribute("href") === current) link.classList.add("active");
  });
}

function openAuthModal(mode = "signup") {
  const modal = qs("#authModal");
  if (!modal) return;
  setAuthMode(mode);
  modal.classList.remove("hidden");
}

function closeAuthModal() {
  qs("#authModal")?.classList.add("hidden");
}

function setAuthMode(mode) {
  const title = qs("#authTitle");
  const subtitle = qs("#authSubtitle");

  qsa("[data-auth-tab]").forEach((tab) => {
    tab.classList.toggle("active", tab.dataset.authTab === mode);
  });

  qsa("[data-auth-pane]").forEach((pane) => {
    pane.classList.toggle("hidden", pane.dataset.authPane !== mode);
  });

  if (title) title.textContent = mode === "login" ? "Sign in" : "Create your account";
  if (subtitle) {
    subtitle.textContent = mode === "login"
      ? "Welcome back. Continue earning toward your next skin."
      : "Start earning coins toward CS2 skins.";
  }
}

function initAuthModal() {
  const modal = qs("#authModal");
  if (!modal) return;

  document.addEventListener("click", async (event) => {
    const openButton = event.target.closest("[data-open-auth]");
    if (openButton) {
      event.preventDefault();
      openAuthModal(openButton.dataset.openAuth || "signup");
      return;
    }

    if (event.target.closest("[data-close-auth]")) {
      event.preventDefault();
      closeAuthModal();
      return;
    }

    if (event.target === modal) {
      closeAuthModal();
      return;
    }

    const tab = event.target.closest("[data-auth-tab]");
    if (tab) {
      event.preventDefault();
      setAuthMode(tab.dataset.authTab);
    }
  });

  qs("#modalSignupForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();

    const email = qs("#modalSignupEmail")?.value.trim();
    const password = qs("#modalSignupPassword")?.value;

    const { data, error } = await sb.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: getPageUrl("auth-confirm.html")
      }
    });
    if (error) return showMessage(error.message, "error");

    if (data?.session) {
      showMessage("Account created and signed in.", "success");
      closeAuthModal();
      await refreshAll();
      return;
    }

    showMessage("Account created. Check your inbox and click the SkinQuest confirmation link.", "success");
    setAuthMode("login");
  });

  qs("#modalLoginForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();

    const email = qs("#modalLoginEmail")?.value.trim();
    const password = qs("#modalLoginPassword")?.value;

    const { error } = await sb.auth.signInWithPassword({ email, password });
    if (error) return showMessage(error.message, "error");

    closeAuthModal();
    await refreshAll();
  });

  qs("#googleLoginButton")?.addEventListener("click", () => {
    showMessage("Google sign-in is planned for version 11.5. Use email sign-in for now.");
  });

  qs("#steamLoginButton")?.addEventListener("click", () => {
    showMessage("Steam sign-in is planned for version 11.5. Use email sign-in for now.");
  });
}

async function updateNavAuthState() {
  const actions = qs("#navAuthActions");
  const user = await getSessionUser();
  currentUser = user;
  currentIsAdmin = await fetchAdminStatus(user);
  updateAdminVisibility(user);

  if (!actions) return;
  actions.classList.remove("auth-loading");

  if (!user) {
    actions.innerHTML = `
      <button class="nav-login nav-clickable" type="button" data-open-auth="login">Sign in</button>
      <button class="button button-primary nav-cta" type="button" data-open-auth="signup">Sign up</button>
    `;
    return;
  }

  let coins = 0;
  try {
    const profile = await ensureProfile(user);
    currentProfile = profile;
    coins = Number(profile.points_balance || 0);
  } catch {}

  const email = user.email || "Account";
  const adminLink = isAdmin(user) ? `<a href="admin.html">Admin panel</a>` : "";

  actions.innerHTML = `
    <a class="coin-pill" href="dashboard.html" aria-label="Your coin balance">
      ${coinIcon("coin-icon-small")}
      <strong>${coins.toLocaleString()}</strong>
      <span>coins</span>
    </a>
    <div class="account-menu" data-account-menu>
      <button class="account-trigger" type="button" id="accountMenuButton" aria-haspopup="true" aria-expanded="false">
        <span class="account-avatar">${escapeHtml(userInitial(user))}</span>
        <span class="account-trigger-copy">
          <strong>${escapeHtml(email.split("@")[0] || "Account")}</strong>
        </span>
        <span class="account-chevron">⌄</span>
      </button>
      <div class="account-dropdown hidden" id="accountDropdown" role="menu">
        <div class="account-dropdown-head">
          <span class="account-avatar large">${escapeHtml(userInitial(user))}</span>
          <div>
            <strong>${escapeHtml(email)}</strong>
            <small>${coins.toLocaleString()} coins available</small>
          </div>
        </div>
        <a href="dashboard.html">Dashboard</a>
        <a href="settings.html">Settings</a>
        <a href="rewards.html">Rewards</a>
        <a href="earn.html">Earn coins</a>
        ${adminLink}
        <button type="button" id="navLogoutButton">Log out</button>
      </div>
    </div>
  `;

  const menuButton = qs("#accountMenuButton");
  const dropdown = qs("#accountDropdown");
  menuButton?.addEventListener("click", (event) => {
    event.stopPropagation();
    const open = dropdown?.classList.toggle("hidden") === false;
    menuButton.setAttribute("aria-expanded", String(open));
  });

  if (!window.__skinquestAccountMenuCloseBound) {
    window.__skinquestAccountMenuCloseBound = true;
    document.addEventListener("click", (event) => {
      if (!event.target.closest("[data-account-menu]")) {
        qs("#accountDropdown")?.classList.add("hidden");
        qs("#accountMenuButton")?.setAttribute("aria-expanded", "false");
      }
    });
  }

  qs("#navLogoutButton")?.addEventListener("click", async () => {
    await sb.auth.signOut();
    location.href = "index.html";
  });
}

async function updateHomeAuthState() {
  const guest = qs("[data-guest-home]");
  const authed = qs("[data-user-home]");
  if (!guest || !authed) return;

  const user = await getSessionUser();

  if (!user) {
    guest.classList.remove("hidden");
    authed.classList.add("hidden");
    const homeCoins = qs("[data-home-coins]");
    const homeLevel = qs("[data-home-level]");
    const homePending = qs("[data-home-pending]");
    if (homeCoins) homeCoins.textContent = "0";
    if (homeLevel) homeLevel.textContent = "1";
    if (homePending) homePending.textContent = "0";
    return;
  }

  guest.classList.add("hidden");
  authed.classList.remove("hidden");

  try {
    const profile = await ensureProfile(user);
    const totalEarned = await getTotalEarned(user.id);
    const { data: redemptions } = await sb
      .from("redemption_requests")
      .select("status")
      .eq("user_id", user.id);

    const homeCoins = qs("[data-home-coins]");
    const homeLevel = qs("[data-home-level]");
    const homePending = qs("[data-home-pending]");
    if (homeCoins) homeCoins.textContent = Number(profile.points_balance || 0).toLocaleString();
    if (homeLevel) homeLevel.textContent = calculateLevel(totalEarned);
    if (homePending) homePending.textContent = (redemptions || []).filter((item) => ["pending", "reviewing", "trade_sent"].includes(item.status)).length;
  } catch {}
}

async function initOfferwall() {
  const cpxButton = qs("#openCpxWall");
  if (!cpxButton) return;

  const user = await getSessionUser();

  if (!user) {
    cpxButton.href = "#";
    cpxButton.classList.add("needs-login");
    cpxButton.addEventListener("click", (event) => {
      event.preventDefault();
      openAuthModal("signup");
    });
    return;
  }

  cpxButton.classList.remove("needs-login");
  cpxButton.href = `https://offers.cpx-research.com/index.php?app_id=${CPX_APP_ID}&ext_user_id=${encodeURIComponent(user.id)}`;
  cpxButton.target = "_blank";
  cpxButton.rel = "noopener";
}

async function loadRewards() {
  const attempts = [
    () => sb.from("reward_items").select("*").eq("active", true).order("sort_order", { ascending: true }).order("points_coins", { ascending: true }),
    () => sb.from("reward_items").select("*").eq("active", true).order("points_coins", { ascending: true }),
    () => sb.from("reward_items").select("*").eq("active", true).order("points_cost", { ascending: true }),
    () => sb.from("reward_items").select("*").eq("active", true)
  ];

  let lastError = null;
  for (const attempt of attempts) {
    const { data, error } = await attempt();
    if (!error) {
      rewardItems = (data || []).sort((a, b) => {
        const aSort = Number(a.sort_order ?? 0);
        const bSort = Number(b.sort_order ?? 0);
        if (aSort !== bSort) return aSort - bSort;
        return getRewardCost(a) - getRewardCost(b);
      });
      return;
    }
    lastError = error;
  }

  throw lastError || new Error("Could not load rewards.");
}

function getRewardRarity(item) {
  const raw = (item.rarity || item.rarity_key || "").toString().trim();
  const key = raw.toLowerCase().replace(/[^a-z]/g, "");
  const labels = {
    consumer: "Consumer",
    industrial: "Industrial",
    milspec: "Mil-Spec",
    restricted: "Restricted",
    classified: "Classified",
    covert: "Covert",
    contraband: "Contraband"
  };

  if (!key) return null;
  return { key: labels[key] ? key : "milspec", label: labels[key] || raw };
}

function getRewardCost(item) {
  const cost = Number(item.points_coins ?? item.points_cost ?? 0);
  return Number.isFinite(cost) ? cost : 0;
}

function getRequestCost(item) {
  const cost = Number(item.points_cost ?? item.points_coins ?? 0);
  return Number.isFinite(cost) ? cost : 0;
}

function rarityClass(item) {
  const rarity = getRewardRarity(item);
  return rarity ? `rarity-${rarity.key}` : "";
}

function shortSkinName(name = "") {
  if (name.includes("AK-47")) return "AK";
  if (name.includes("AWP")) return "AWP";
  if (name.includes("M4")) return "M4";
  if (name.includes("USP")) return "USP";
  if (name.includes("Glock")) return "G18";
  if (name.includes("P250")) return "P250";
  if (name.includes("Desert Eagle")) return "DE";
  return "CS";
}

function getRewardImage(item) {
  return String(item.image_url || item.image || item.icon_url || "").replaceAll("\\", "/");
}

function getRewardCondition(item) {
  return item.condition || item.wear || "";
}

function getRewardTotalStock(item) {
  if (item.quantity_total !== null && item.quantity_total !== undefined && item.quantity_total !== "") {
    const total = Number(item.quantity_total);
    return Number.isFinite(total) ? total : null;
  }
  if (item.quantity !== null && item.quantity !== undefined && item.quantity !== "") {
    const quantity = Number(item.quantity);
    return Number.isFinite(quantity) ? quantity : null;
  }
  return null;
}

function getRewardReservedStock(item) {
  const reserved = Number(item.quantity_reserved || 0);
  return Number.isFinite(reserved) ? Math.max(0, reserved) : 0;
}

function getRewardAvailableStock(item) {
  const total = getRewardTotalStock(item);
  if (total === null) return null;
  return Math.max(0, total - getRewardReservedStock(item));
}

function rewardIsOutOfStock(item) {
  const available = getRewardAvailableStock(item);
  return available !== null && available <= 0;
}

function renderRewardArt(item) {
  const image = getRewardImage(item);
  const name = escapeHtml(item.name || "CS2 reward");

  if (!image) {
    return `<div class="reward-art reward-art-placeholder"><span class="skin-abbrev">${shortSkinName(item.name || "")}</span></div>`;
  }

  return `
    <div class="reward-art has-image">
      <img src="${escapeHtml(image)}" alt="${name}" loading="lazy" onerror="this.closest('.reward-art').classList.add('image-failed'); this.remove();" />
      <span class="skin-abbrev fallback-abbrev">${shortSkinName(item.name || "")}</span>
    </div>
  `;
}

async function updateRewardAccountNotice() {
  const notice = qs("#rewardAccountNotice");
  if (!notice) return;

  const user = await getSessionUser();
  if (!user) {
    notice.className = "reward-account-notice";
    notice.innerHTML = `
      <div>
        <strong>Sign in before redeeming.</strong>
        <span>Create an account or sign in so rewards can be connected to you.</span>
      </div>
      <button class="button button-primary" type="button" data-open-auth="login">Sign in</button>
    `;
    return;
  }

  try {
    const profile = await ensureProfile(user);
    if (!profile?.steam_trade_url || !isValidSteamTradeUrl(profile.steam_trade_url)) {
      notice.className = "reward-account-notice warning";
      notice.innerHTML = `
        <div>
          <strong>Add your Steam trade URL before redeeming.</strong>
          <span>SkinQuest needs your Steam trade link so the admin can send your reward after review.</span>
        </div>
        <a class="button button-primary" href="settings.html#tradeForm">Add trade link</a>
      `;
      return;
    }

    notice.className = "reward-account-notice hidden";
    notice.innerHTML = "";
  } catch (error) {
    notice.className = "reward-account-notice warning";
    notice.innerHTML = `
      <div>
        <strong>Account setup needs attention.</strong>
        <span>${escapeHtml(error.message || "Could not check your profile.")}</span>
      </div>
    `;
  }
}

function getRewardStockSortValue(item) {
  const available = getRewardAvailableStock(item);
  if (available === null) return 999999;
  return available;
}

function sortRewardsForShop(items, sortValue) {
  return [...items].sort((a, b) => {
    const aOut = rewardIsOutOfStock(a) ? 1 : 0;
    const bOut = rewardIsOutOfStock(b) ? 1 : 0;
    if (aOut !== bOut) return aOut - bOut;

    if (sortValue === "price-asc") return getRewardCost(a) - getRewardCost(b);
    if (sortValue === "price-desc") return getRewardCost(b) - getRewardCost(a);
    if (sortValue === "stock-desc") return getRewardStockSortValue(b) - getRewardStockSortValue(a);
    if (sortValue === "name-asc") return String(a.name || "").localeCompare(String(b.name || ""));

    const aSort = Number(a.sort_order ?? 0);
    const bSort = Number(b.sort_order ?? 0);
    if (aSort !== bSort) return aSort - bSort;
    return getRewardCost(a) - getRewardCost(b);
  });
}

function renderRewards() {
  const grid = qs("#rewardsGrid");
  if (!grid) return;

  const search = qs("#skinSearch");
  const filter = qs("#priceFilter");
  const sort = qs("#sortFilter");

  function apply() {
    const query = (search?.value || "").toLowerCase().trim();
    const priceFilter = filter?.value || "all";
    const sortValue = sort?.value || "price-desc";

    const filtered = rewardItems.filter((item) => {
      const haystack = [item.name, item.description, item.rarity, item.condition, item.market_name].filter(Boolean).join(" ").toLowerCase();
      const cost = getRewardCost(item);
      const matchesSearch = !query || haystack.includes(query);
      const matchesPrice =
        priceFilter === "all" ||
        (priceFilter === "low" && cost < 500) ||
        (priceFilter === "mid" && cost >= 500 && cost <= 1200) ||
        (priceFilter === "high" && cost > 1200);

      return matchesSearch && matchesPrice;
    });

    const sorted = sortRewardsForShop(filtered, sortValue);

    if (sorted.length === 0) {
      grid.innerHTML = `<div class="empty-state">No rewards found. Try another search or price filter.</div>`;
      return;
    }

    grid.innerHTML = sorted.map((item) => {
      const rarity = getRewardRarity(item);
      const condition = getRewardCondition(item);
      const total = getRewardTotalStock(item);
      const reserved = getRewardReservedStock(item);
      const available = getRewardAvailableStock(item);
      const outOfStock = rewardIsOutOfStock(item);
      const stockText = available === null ? "In stock" : `${available} available`;
      const description = item.description || item.market_name || "Manual Steam trade after review";

      return `
        <article class="reward-card steam-item ${rarityClass(item)} ${outOfStock ? "is-out" : ""}">
          ${renderRewardArt(item)}
          <div class="reward-info">
            <div class="reward-title-row">
              ${rarity ? `<span class="rarity-badge">${escapeHtml(rarity.label)}</span>` : ""}
              ${condition ? `<span class="condition-badge">${escapeHtml(condition)}</span>` : ""}
            </div>
            <h2>${escapeHtml(item.name)}</h2>
            <p class="muted reward-description">${escapeHtml(description)}</p>
            <div class="reward-meta">
              <span class="price">${coinIcon("coin-icon-small")} ${getRewardCost(item).toLocaleString()} coins</span>
              <span class="stock-pill ${outOfStock ? "stock-out" : ""}">${outOfStock ? "Out of stock" : escapeHtml(stockText)}</span>
              ${total !== null && reserved > 0 ? `<span class="stock-pill reserved-stock">${reserved} reserved</span>` : ""}
            </div>
            <div class="reward-actions">
              <button class="button button-primary" type="button" data-redeem="${item.id}" ${outOfStock ? "disabled" : ""}>
                ${outOfStock ? "Unavailable" : "Redeem"}
              </button>
            </div>
          </div>
        </article>
      `;
    }).join("");

    qsa("[data-redeem]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        requestRedeem(Number(button.dataset.redeem), button);
      });
    });
  }

  search?.addEventListener("input", apply);
  filter?.addEventListener("change", apply);
  sort?.addEventListener("change", apply);
  apply();
}

async function requestRedeem(rewardId, sourceButton = null) {
  const user = await getSessionUser();
  if (!user) {
    openAuthModal("signup");
    return;
  }

  let profile;
  try {
    profile = await ensureProfile(user);
  } catch (error) {
    showMessage("Could not prepare your account profile. Please refresh and try again, or contact support if it keeps happening.", "error");
    return;
  }

  const reward = rewardItems.find((item) => Number(item.id) === Number(rewardId));
  if (!reward) return;

  if (!profile.steam_trade_url) {
    const goDashboard = await showConfirm(
      "Before you can redeem, add your Steam trade URL in Settings. Without it, SkinQuest does not know where to send the skin.",
      { title: "Add your Steam trade link first", confirmText: "Add trade link", cancelText: "Stay on rewards", icon: "↗" }
    );
    if (goDashboard) location.href = "settings.html#tradeForm";
    return;
  }

  if (!isValidSteamTradeUrl(profile.steam_trade_url)) {
    const goDashboard = await showConfirm(
      "Your saved Steam trade URL looks incomplete. It must be the full Steam trade offer link with both partner and token.",
      { title: "Fix your Steam trade link", confirmText: "Fix trade link", cancelText: "Stay on rewards", icon: "!" }
    );
    if (goDashboard) location.href = "settings.html#tradeForm";
    return;
  }

  if (Number(profile.points_balance || 0) < getRewardCost(reward)) {
    showMessage(`Not enough coins yet. You have ${Number(profile.points_balance || 0).toLocaleString()} coins and this costs ${getRewardCost(reward).toLocaleString()}.`, "error");
    return;
  }

  if (rewardIsOutOfStock(reward)) {
    showMessage("That reward is out of stock.");
    await loadRewards();
    renderRewards();
    return;
  }

  const available = getRewardAvailableStock(reward);
  const stockLine = available === null ? "" : ` Available after this request: ${Math.max(0, available - 1)}.`;
  const confirmed = await showConfirm(
    `Redeem ${reward.name} for ${getRewardCost(reward).toLocaleString()} coins? Coins are deducted now and held while your request is pending.${stockLine}`,
    {
      title: "Redeem reward",
      confirmText: "Redeem",
      cancelText: "Not yet",
      icon: coinIcon("coin-icon-confirm")
    }
  );
  if (!confirmed) return;

  if (sourceButton) {
    sourceButton.disabled = true;
    sourceButton.dataset.originalText = sourceButton.textContent;
    sourceButton.textContent = "Redeeming...";
  }

  const { error } = await sb.rpc("redeem_reward", { p_reward_id: rewardId });

  if (sourceButton) {
    sourceButton.disabled = false;
    sourceButton.textContent = sourceButton.dataset.originalText || "Redeem";
  }

  if (error) {
    const errorText = String(error.message || "");
    if (errorText.toLowerCase().includes("trade url") || errorText.toLowerCase().includes("trade link")) {
      const goDashboard = await showConfirm(
        "Your reward request was not created because your Steam trade URL is missing or was not saved correctly. Add it on the Dashboard, save it, then try redeeming again.",
        { title: "Steam trade link required", confirmText: "Open Dashboard", cancelText: "Stay on rewards", icon: "↗" }
      );
      if (goDashboard) location.href = "settings.html#tradeForm";
      await updateRewardAccountNotice();
      return;
    }
    return showMessage("Could not create the redeem request. Please refresh, check your trade link, and try again.", "error");
  }

  showMessage("Redeem request created. Coins were deducted and stock was reserved for manual review.", "success");
  await loadRewards();
  renderRewards();
  await updateRewardAccountNotice();
  await refreshAll();
}

function isValidSteamTradeUrl(url) {
  if (!url) return false;
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();
    return host === "steamcommunity.com" &&
      parsed.pathname.startsWith("/tradeoffer/new/") &&
      parsed.searchParams.has("partner") &&
      parsed.searchParams.has("token");
  } catch {
    return false;
  }
}

async function saveSteamTradeUrlForUser(user, steamTradeUrl) {
  if (!user?.id) throw new Error("You need to sign in first.");

  // Preferred route. This avoids the silent '0 rows updated' problem when a profile row is missing.
  const { error: rpcError } = await sb.rpc("save_skinquest_trade_url", { p_trade_url: steamTradeUrl });
  if (!rpcError) return;

  // Fallback route if the RPC is unavailable.
  await ensureProfile(user);
  const { data, error } = await sb
    .from("profiles")
    .update({ steam_trade_url: steamTradeUrl })
    .eq("id", user.id)
    .select("id, steam_trade_url")
    .maybeSingle();

  if (error) throw new Error("Could not save your Steam trade URL. Please try again.");
  if (!data) throw new Error("Could not save your Steam trade URL. Refresh the page and try again.");
}


function getStoredNotificationPreferences(userId) {
  const defaults = {
    reward_updates: true,
    offer_issues: true,
    product_updates: false
  };
  if (!userId) return defaults;
  try {
    const stored = JSON.parse(localStorage.getItem(`skinquest_notification_preferences_${userId}`) || "{}");
    return { ...defaults, ...stored };
  } catch {
    return defaults;
  }
}

function saveStoredNotificationPreferences(userId, prefs) {
  if (!userId) return;
  localStorage.setItem(`skinquest_notification_preferences_${userId}`, JSON.stringify(prefs));
}

async function trySaveNotificationPreferences(user, prefs) {
  saveStoredNotificationPreferences(user.id, prefs);

  // Final v11 SQL includes this RPC. Older databases can ignore the failure safely.
  try {
    await sb.rpc("save_account_settings", {
      p_notification_reward_updates: !!prefs.reward_updates,
      p_notification_offer_issues: !!prefs.offer_issues,
      p_notification_product_updates: !!prefs.product_updates
    });
  } catch {}
}

function updateRedeemBlocker(profile) {
  const panel = qs("#redeemBlockerPanel");
  if (!panel) return;
  const hasTrade = !!profile?.steam_trade_url && isValidSteamTradeUrl(profile.steam_trade_url);
  panel.classList.toggle("hidden", hasTrade);
}

async function initSettingsPage() {
  if (!qs("#settingsAuthSection") && !qs("#notificationSettingsForm")) return;

  qsa("[data-future-service]").forEach((button) => {
    button.addEventListener("click", () => {
      showMessage(`${button.dataset.futureService} linking is planned for version 11.5.`);
    });
  });

  qs("#notificationSettingsForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const user = await getSessionUser();
    if (!user) return openAuthModal("login");

    const prefs = {
      reward_updates: !!qs("#notifyRewardUpdates")?.checked,
      offer_issues: !!qs("#notifyOfferIssues")?.checked,
      product_updates: !!qs("#notifyProductUpdates")?.checked
    };

    await trySaveNotificationPreferences(user, prefs);
    showMessage("Notification preferences saved.", "success");
  });

  await refreshSettingsPage();
}

async function refreshSettingsPage() {
  const authSection = qs("#settingsAuthSection");
  const accountSection = qs("#settingsAccountSection");
  const loadingSection = qs("#settingsLoadingSection");
  if (!authSection || !accountSection) return;

  const user = await getSessionUser();
  loadingSection?.classList.add("hidden");
  if (!user) {
    authSection.classList.remove("hidden");
    accountSection.classList.add("hidden");
    return;
  }

  authSection.classList.add("hidden");
  accountSection.classList.remove("hidden");

  const profile = await ensureProfile(user).catch(() => null);
  const storedPrefs = getStoredNotificationPreferences(user.id);
  const prefs = {
    reward_updates: profile?.notification_reward_updates ?? storedPrefs.reward_updates,
    offer_issues: profile?.notification_offer_issues ?? storedPrefs.offer_issues,
    product_updates: profile?.notification_product_updates ?? storedPrefs.product_updates
  };

  const email = user.email || "Account";
  const shortId = user.id ? `${user.id.slice(0, 8)}...${user.id.slice(-6)}` : "Unknown id";

  const avatar = qs("#settingsAvatar");
  if (avatar) avatar.textContent = userInitial(user);
  const emailEl = qs("#settingsEmail");
  if (emailEl) emailEl.textContent = email;
  const idEl = qs("#settingsUserId");
  if (idEl) idEl.textContent = `User ID: ${shortId}`;

  const tradeUrl = qs("#tradeUrl");
  if (tradeUrl) tradeUrl.value = profile?.steam_trade_url || "";

  const setChecked = (selector, value) => {
    const el = qs(selector);
    if (el) el.checked = !!value;
  };
  setChecked("#notifyRewardUpdates", prefs.reward_updates);
  setChecked("#notifyOfferIssues", prefs.offer_issues);
  setChecked("#notifyProductUpdates", prefs.product_updates);
}

function initSupportWidget() {
  if (document.querySelector("[data-support-widget]")) return;

  const shell = document.createElement("div");
  shell.className = "support-widget";
  shell.dataset.supportWidget = "true";
  shell.innerHTML = `
    <button class="support-fab" type="button" aria-expanded="false" aria-label="Open support" data-support-toggle>
      <span>?</span>
    </button>
    <section class="support-panel" aria-label="Support panel" aria-hidden="true" data-support-panel>
      <div class="support-panel-head">
        <div>
          <strong>Need help?</strong>
          <p>Support usually replies within 24h.</p>
        </div>
        <button type="button" aria-label="Close support" data-support-close>×</button>
      </div>
      <form class="support-form" data-support-form>
        <label>Topic
          <select data-support-topic>
            <option>Coins did not arrive</option>
            <option>Reward request</option>
            <option>Trade URL problem</option>
            <option>Account issue</option>
            <option>Other</option>
          </select>
        </label>
        <label>Message
          <textarea data-support-message rows="4" placeholder="Tell us what happened. Include reward name, offer, or trade details if relevant."></textarea>
        </label>
        <button class="button button-primary" type="submit">Send request</button>
        <p class="fine-print">Signed-in requests are saved to support. Support usually replies within 24h.</p>
      </form>
    </section>
  `;

  document.body.appendChild(shell);

  const toggle = shell.querySelector("[data-support-toggle]");
  const panel = shell.querySelector("[data-support-panel]");
  const close = shell.querySelector("[data-support-close]");
  const setOpen = (open) => {
    panel.classList.toggle("open", open);
    panel.setAttribute("aria-hidden", String(!open));
    toggle.classList.toggle("open", open);
    toggle.setAttribute("aria-expanded", String(open));
  };

  toggle.addEventListener("click", () => setOpen(!panel.classList.contains("open")));
  close.addEventListener("click", () => setOpen(false));

  shell.querySelector("[data-support-form]")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const topic = shell.querySelector("[data-support-topic]")?.value || "Support request";
    const message = shell.querySelector("[data-support-message]")?.value.trim();
    if (!message) return showMessage("Write a short message before sending support.", "error");

    const user = await getSessionUser();
    const draft = [
      `Topic: ${topic}`,
      `Account: ${user?.email || "Not signed in"}`,
      `Page: ${location.href}`,
      "",
      message
    ].join("\n");

    if (user?.id) {
      try {
        const { error } = await sb.from("support_requests").insert({
          user_id: user.id,
          topic,
          message,
          page_url: location.href
        });
        if (!error) {
          showMessage("Support request sent. Support usually replies within 24h.", "success");
          shell.querySelector("[data-support-message]").value = "";
          setOpen(false);
          return;
        }
      } catch {}
    }

    try {
      await navigator.clipboard?.writeText(draft);
    } catch {}

    if (SUPPORT_EMAIL) {
      const subject = encodeURIComponent(`SkinQuest support - ${topic}`);
      const body = encodeURIComponent(draft);
      location.href = `mailto:${SUPPORT_EMAIL}?subject=${subject}&body=${body}`;
      showMessage("Opening your email app with the support message.", "success");
    } else {
      showMessage("Support message copied. Send it to the SkinQuest team through the current support channel.", "success");
    }

    shell.querySelector("[data-support-message]").value = "";
  });
}

async function initDashboard() {
  const tradeForm = qs("#tradeForm");
  if (tradeForm) {
    tradeForm.addEventListener("submit", async (event) => {
      event.preventDefault();

      const user = await getSessionUser();
      if (!user) return openAuthModal("login");

      const steamTradeUrl = qs("#tradeUrl")?.value.trim();
      if (steamTradeUrl && !isValidSteamTradeUrl(steamTradeUrl)) {
        return showMessage("That does not look like a valid Steam trade URL. It should include steamcommunity.com/tradeoffer/new/?partner=...&token=...");
      }

      try {
        await saveSteamTradeUrlForUser(user, steamTradeUrl);
      } catch (error) {
        return showMessage(error.message, "error");
      }

      showMessage("Steam trade URL saved.", "success");
      await refreshAll();
    });
  }

  qs("#logoutButton")?.addEventListener("click", async () => {
    await sb.auth.signOut();
    location.href = "index.html";
  });

  await refreshDashboard();
}

async function refreshDashboard() {
  const authSection = qs("#authSection");
  const accountSection = qs("#accountSection");
  const loadingSection = qs("#dashboardLoadingSection");
  if (!authSection || !accountSection) return;

  const user = await getSessionUser();
  loadingSection?.classList.add("hidden");

  if (!user) {
    authSection.classList.remove("hidden");
    accountSection.classList.add("hidden");
    return;
  }

  authSection.classList.add("hidden");
  accountSection.classList.remove("hidden");

  let profile = await ensureProfile(user);
  try {
    const bonus = await claimLevelRewards();
    if (Number(bonus?.bonus_awarded || 0) > 0) {
      showMessage(`Level reward unlocked: +${Number(bonus.bonus_awarded).toLocaleString()} coins.`, "success");
      profile = await ensureProfile(user);
    }
  } catch (error) {
    console.warn("Level reward check failed:", error);
  }
  const totalEarned = await getTotalEarned(user.id);
  const progress = getLevelProgress(totalEarned);

  const setText = (selector, value) => {
    const el = qs(selector);
    if (el) el.textContent = value;
  };

  setText("#accountEmail", user.email || "Unknown");
  setText("#balanceDisplay", Number(profile.points_balance || 0).toLocaleString());
  setText("#totalEarnedDisplay", Number(totalEarned).toLocaleString());
  setText("#levelDisplay", progress.level);
  setText("#xpDisplay", `${Number(totalEarned - progress.currentFloor).toLocaleString()} / ${COINS_PER_LEVEL.toLocaleString()} earned coins`);
  setText("#levelText", `Level ${progress.level}`);
  setText("#nextLevelText", `${Number(Math.max(0, progress.nextFloor - totalEarned)).toLocaleString()} coins to Level ${progress.level + 1}`);

  const xpBar = qs("#xpBarFill");
  if (xpBar) xpBar.style.width = `${progress.progress}%`;

  updateRedeemBlocker(profile);

  const { data: redemptions, error } = await sb
    .from("redemption_requests")
    .select("*")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  if (!error) {
    setText("#pendingDisplay", (redemptions || []).filter((item) => ["pending", "reviewing", "trade_sent"].includes(item.status)).length);
    renderRedeemHistory(redemptions || []);
  }

  await renderCoinHistory(user.id);
}

function renderRedeemHistory(redemptions) {
  const redeemHistory = qs("#redeemHistory");
  if (!redeemHistory) return;

  if (!redemptions || redemptions.length === 0) {
    redeemHistory.className = "empty-state";
    redeemHistory.innerHTML = "No redeem history yet.";
    return;
  }

  const rows = redemptions.map((item, index) => `
    <div class="redeem-row ${index >= 5 ? "redeem-extra hidden" : ""}">
      <div>
        <strong>${escapeHtml(item.reward_name)}</strong>
        <p class="muted">${formatDate(item.created_at)} · ${getRequestCost(item).toLocaleString()} coins</p>
        ${item.trade_offer_url ? `<a class="mini-link" target="_blank" rel="noopener" href="${escapeHtml(item.trade_offer_url)}">Open trade offer</a>` : ""}
        ${item.admin_note ? `<p class="muted admin-note-view">${escapeHtml(item.admin_note)}</p>` : ""}
      </div>
      <span class="status-pill status-${escapeHtml(item.status)}">${escapeHtml(formatStatus(item.status))}</span>
    </div>
  `).join("");

  const showMore = redemptions.length > 5 ? `
    <button class="button button-ghost history-show-more" type="button" data-show-more-redeems>
      Show more
    </button>
  ` : "";

  redeemHistory.className = "redeem-list";
  redeemHistory.innerHTML = `${rows}${showMore}`;
  redeemHistory.querySelector("[data-show-more-redeems]")?.addEventListener("click", (event) => {
    redeemHistory.querySelectorAll(".redeem-extra").forEach((row) => row.classList.remove("hidden"));
    event.currentTarget.remove();
  });
}

async function renderCoinHistory(userId) {
  const coinHistory = qs("#coinHistory");
  if (!coinHistory) return;

  const { data, error } = await sb
    .from("coin_adjustments")
    .select("amount, reason, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    coinHistory.className = "empty-state";
    coinHistory.textContent = "Could not load coin history.";
    return;
  }

  if (!data || data.length === 0) {
    coinHistory.className = "empty-state";
    coinHistory.textContent = "No coin history yet.";
    return;
  }

  const rows = data.map((item, index) => {
    const amount = Number(item.amount || 0);
    return `
      <div class="coin-history-row ${amount >= 0 ? "positive" : "negative"} ${index >= 5 ? "history-extra hidden" : ""}">
        <strong>${amount >= 0 ? "+" : ""}${amount.toLocaleString()} coins</strong>
        <span>${escapeHtml(item.reason || "Coin adjustment")}</span>
        <small>${formatDate(item.created_at)}</small>
      </div>
    `;
  }).join("");

  const showMore = data.length > 5 ? `
    <button class="button button-ghost history-show-more" type="button" data-show-more-history>
      Show more
    </button>
  ` : "";

  coinHistory.className = "coin-history-list";
  coinHistory.innerHTML = `${rows}${showMore}`;

  coinHistory.querySelector("[data-show-more-history]")?.addEventListener("click", (event) => {
    coinHistory.querySelectorAll(".history-extra").forEach((row) => row.classList.remove("hidden"));
    event.currentTarget.remove();
  });
}

function formatStatus(status) {
  const labels = {
    pending: "Pending",
    reviewing: "Reviewing",
    trade_sent: "Trade sent",
    completed: "Completed",
    rejected: "Rejected",
    refunded: "Refunded",
    cancelled: "Cancelled"
  };
  return labels[status] || status || "Unknown";
}

async function initAuthConfirmPage() {
  const statusBox = qs("#authConfirmStatus");
  if (!statusBox) return;

  const title = qs("#authConfirmTitle");
  const copy = qs("#authConfirmCopy");
  const actions = qs("#authConfirmActions");

  function setState(state, heading, message) {
    statusBox.className = `panel auth-result auth-result-${state}`;
    if (title) title.textContent = heading;
    if (copy) copy.textContent = message;
  }

  setState("loading", "Confirming your email...", "Finishing your SkinQuest sign-in. This usually takes a second.");

  try {
    const params = new URLSearchParams(location.search);
    const code = params.get("code");

    if (code) {
      const { error } = await sb.auth.exchangeCodeForSession(code);
      if (error && !String(error.message || "").toLowerCase().includes("already")) throw error;
      history.replaceState({}, document.title, location.pathname);
    }

    await new Promise((resolve) => setTimeout(resolve, 250));
    const { data, error } = await sb.auth.getSession();
    if (error) throw error;

    const user = data?.session?.user || await getSessionUser();
    if (!user) {
      setState("warning", "Email link opened", "Your email link was opened, but no active session was found. Try signing in now. If Supabase still sends you here, check the redirect URL settings.");
      if (actions) actions.innerHTML = `<button class="button button-primary" data-open-auth="login">Sign in</button><a class="button button-ghost" href="index.html">Home</a>`;
      return;
    }

    await ensureProfile(user);
    setState("success", "Email confirmed", "Your SkinQuest account is ready. You can now earn coins and redeem rewards.");
    if (actions) actions.innerHTML = `<a class="button button-primary" href="dashboard.html">Go to dashboard</a><a class="button button-ghost" href="rewards.html">View rewards</a>`;
    await updateNavAuthState();
  } catch (error) {
    setState("error", "Could not confirm email", error.message || "The confirmation link could not be processed.");
    if (actions) actions.innerHTML = `<button class="button button-primary" data-open-auth="login">Try signing in</button><a class="button button-ghost" href="index.html">Home</a>`;
  }
}

function initAdminCoinForm() {
  const form = qs("#adminCoinForm");
  if (!form || form.dataset.bound === "true") return;
  form.dataset.bound = "true";

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const identifier = qs("#coinUserIdentifier")?.value.trim();
    const amount = Number(qs("#coinAmount")?.value || 0);
    const reason = qs("#coinReason")?.value.trim() || "Manual admin adjustment";

    if (!identifier) return showMessage("Enter the user's email or user id.", "error");
    if (!Number.isInteger(amount) || amount === 0) return showMessage("Amount must be a whole number, not 0.", "error");

    const confirmed = await showConfirm(
      `Apply ${amount > 0 ? "+" : ""}${amount.toLocaleString()} coins to ${identifier}?`,
      { title: "Adjust user coins", confirmText: "Apply", cancelText: "Cancel", icon: coinIcon("coin-icon-confirm") }
    );
    if (!confirmed) return;

    const { error } = await sb.rpc("admin_adjust_user_coins", {
      p_user_identifier: identifier,
      p_amount: amount,
      p_reason: reason
    });

    if (error) return showMessage(`Could not adjust coins: ${error.message}`, "error");
    showMessage("Coin adjustment saved.", "success");
    form.reset();
  });
}

async function initAdmin() {
  const locked = qs("#adminLocked");
  const panel = qs("#adminPanel");
  const list = qs("#adminRequests");
  if (!locked || !panel || !list) return;

  const user = await getSessionUser();
  currentIsAdmin = await fetchAdminStatus(user);
  updateAdminVisibility(user);

  if (!isAdmin(user)) {
    locked.classList.remove("hidden");
    panel.classList.add("hidden");
    return;
  }

  locked.classList.add("hidden");
  panel.classList.remove("hidden");

  qs("#refreshAdmin")?.addEventListener("click", async () => {
    await loadAdminRequests();
    await loadAdminRewards();
  });

  qs("#adminStatusFilter")?.addEventListener("change", loadAdminRequests);
  initAdminRewardForm();
  initAdminCoinForm();

  await loadAdminRequests();
  await loadAdminRewards();
}

async function loadAdminRequests() {
  const list = qs("#adminRequests");
  if (!list) return;

  const statusFilter = qs("#adminStatusFilter")?.value || "open";
  let query = sb.from("redemption_requests").select("*").order("created_at", { ascending: false }).limit(100);

  if (statusFilter === "open") {
    query = query.in("status", ["pending", "reviewing", "trade_sent"]);
  } else if (statusFilter !== "all") {
    query = query.eq("status", statusFilter);
  }

  const { data, error } = await query;

  if (error) {
    list.className = "empty-state";
    list.textContent = `Could not load admin requests: ${error.message}`;
    return;
  }

  if (!data || data.length === 0) {
    list.className = "empty-state";
    list.textContent = "No redeem requests found.";
    return;
  }

  list.className = "admin-list";
  list.innerHTML = data.map((item) => `
    <article class="admin-request">
      <div class="admin-request-main">
        <div class="request-topline">
          <strong>${escapeHtml(item.reward_name)}</strong>
          <span class="status-pill status-${escapeHtml(item.status)}">${escapeHtml(formatStatus(item.status))}</span>
        </div>
        <p class="muted">${formatDate(item.created_at)} · ${getRequestCost(item).toLocaleString()} coins · User: ${escapeHtml(item.user_id)}</p>
        <div class="admin-url-block">
          <label>Steam trade URL</label>
          <p class="admin-url">${escapeHtml(item.steam_trade_url || "No trade URL saved")}</p>
        </div>
        <div class="admin-grid-form compact">
          <label>Status
            <select data-request-status="${item.id}">
              ${["pending", "reviewing", "trade_sent", "completed", "rejected", "refunded", "cancelled"].map((status) => `
                <option value="${status}" ${status === item.status ? "selected" : ""}>${formatStatus(status)}</option>
              `).join("")}
            </select>
          </label>
          <label>Trade offer URL / proof
            <input data-request-trade="${item.id}" value="${escapeHtml(item.trade_offer_url || "")}" placeholder="Optional Steam trade/proof link" />
          </label>
          <label class="wide">Admin note
            <input data-request-note="${item.id}" value="${escapeHtml(item.admin_note || "")}" placeholder="Visible note, refund reason, etc." />
          </label>
        </div>
      </div>
      <div class="admin-actions vertical">
        <button class="button button-primary" type="button" data-admin-save="${item.id}">Save status</button>
        <button class="button button-ghost" type="button" data-admin-quick="trade_sent" data-request-id="${item.id}">Trade sent</button>
        <button class="button button-ghost" type="button" data-admin-quick="completed" data-request-id="${item.id}">Completed</button>
        <button class="button button-danger" type="button" data-admin-quick="rejected" data-request-id="${item.id}">Reject + refund</button>
      </div>
    </article>
  `).join("");

  qsa("[data-admin-save]").forEach((button) => {
    button.addEventListener("click", () => saveRequestStatus(Number(button.dataset.adminSave)));
  });

  qsa("[data-admin-quick]").forEach((button) => {
    button.addEventListener("click", async () => {
      const id = Number(button.dataset.requestId);
      const status = button.dataset.adminQuick;
      const statusInput = qs(`[data-request-status="${id}"]`);
      if (statusInput) statusInput.value = status;
      await saveRequestStatus(id);
    });
  });
}

async function saveRequestStatus(id) {
  const status = qs(`[data-request-status="${id}"]`)?.value;
  const adminNote = qs(`[data-request-note="${id}"]`)?.value || "";
  const tradeOfferUrl = qs(`[data-request-trade="${id}"]`)?.value || "";

  if (!status) return;
  if (["rejected", "refunded", "cancelled"].includes(status)) {
    const confirmed = await showConfirm(
      "This will refund coins and release reserved stock if it has not already been done.",
      { title: "Refund request?", confirmText: "Yes, refund", cancelText: "Cancel", danger: true, icon: "↩" }
    );
    if (!confirmed) return;
  }
  if (status === "completed") {
    const confirmed = await showConfirm(
      "This marks the request as completed and finalizes stock if it has not already been done.",
      { title: "Complete request?", confirmText: "Mark completed", cancelText: "Cancel", icon: "✓" }
    );
    if (!confirmed) return;
  }

  const { error } = await sb.rpc("admin_update_redemption_status", {
    p_request_id: id,
    p_status: status,
    p_admin_note: adminNote,
    p_trade_offer_url: tradeOfferUrl
  });

  if (error) return showMessage(`Could not update request status: ${error.message}`, "error");

  showMessage(`Request marked ${formatStatus(status)}.`);
  await loadAdminRequests();
  await loadAdminRewards();
}

function initAdminRewardForm() {
  const form = qs("#adminRewardForm");
  if (!form) return;

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    await saveAdminReward();
  });

  qs("#resetRewardForm")?.addEventListener("click", () => setRewardForm(null));
}

function setRewardForm(item) {
  qs("#rewardFormTitle") && (qs("#rewardFormTitle").textContent = item ? "Edit reward" : "Add reward");
  qs("#rewardId") && (qs("#rewardId").value = item?.id || "");
  qs("#rewardName") && (qs("#rewardName").value = item?.name || "");
  qs("#rewardCost") && (qs("#rewardCost").value = item?.points_coins ?? "");
  qs("#rewardImage") && (qs("#rewardImage").value = item?.image_url || "");
  qs("#rewardTotal") && (qs("#rewardTotal").value = getRewardTotalStock(item || {}) ?? 1);
  qs("#rewardReserved") && (qs("#rewardReserved").value = getRewardReservedStock(item || {}));
  qs("#rewardRarity") && (qs("#rewardRarity").value = item?.rarity || "");
  qs("#rewardCondition") && (qs("#rewardCondition").value = item?.condition || "");
  qs("#rewardSort") && (qs("#rewardSort").value = item?.sort_order ?? 0);
  qs("#rewardDescription") && (qs("#rewardDescription").value = item?.description || "");
  qs("#rewardActive") && (qs("#rewardActive").checked = item?.active ?? true);
}

function getRewardFormPayload() {
  return {
    name: qs("#rewardName")?.value.trim(),
    points_coins: Number(qs("#rewardCost")?.value || 0),
    points_cost: Number(qs("#rewardCost")?.value || 0),
    image_url: qs("#rewardImage")?.value.trim() || null,
    quantity_total: Number(qs("#rewardTotal")?.value || 0),
    quantity_reserved: Number(qs("#rewardReserved")?.value || 0),
    rarity: qs("#rewardRarity")?.value || null,
    condition: qs("#rewardCondition")?.value.trim() || null,
    sort_order: Number(qs("#rewardSort")?.value || 0),
    description: qs("#rewardDescription")?.value.trim() || null,
    active: !!qs("#rewardActive")?.checked
  };
}

async function saveAdminReward() {
  const payload = getRewardFormPayload();
  const id = qs("#rewardId")?.value;

  if (!payload.name) return showMessage("Reward name is required.");
  if (!payload.points_coins || payload.points_coins < 1) return showMessage("Coin price must be at least 1.");
  if (payload.quantity_reserved > payload.quantity_total) return showMessage("Reserved stock cannot be higher than total stock.");

  const query = id
    ? sb.from("reward_items").update(payload).eq("id", id)
    : sb.from("reward_items").insert(payload);

  const { error } = await query;
  if (error) return showMessage(`Could not save reward: ${error.message}`, "error");

  showMessage(id ? "Reward updated." : "Reward created.");
  setRewardForm(null);
  await loadAdminRewards();
  await loadRewards().catch(() => {});
}

async function loadAdminRewards() {
  const list = qs("#adminRewardsList");
  if (!list) return;

  const attempts = [
    () => sb.from("reward_items").select("*").order("active", { ascending: false }).order("sort_order", { ascending: true }).order("points_coins", { ascending: true }),
    () => sb.from("reward_items").select("*").order("active", { ascending: false }).order("points_coins", { ascending: true }),
    () => sb.from("reward_items").select("*").order("active", { ascending: false }).order("points_cost", { ascending: true }),
    () => sb.from("reward_items").select("*")
  ];

  let data = null;
  let error = null;
  for (const attempt of attempts) {
    const result = await attempt();
    if (!result.error) {
      data = result.data;
      error = null;
      break;
    }
    error = result.error;
  }

  if (error) {
    list.className = "empty-state";
    list.textContent = `Could not load admin rewards: ${error.message}`;
    return;
  }

  adminRewardItems = (data || []).sort((a, b) => {
    if (Boolean(a.active) !== Boolean(b.active)) return a.active ? -1 : 1;
    const aSort = Number(a.sort_order ?? 0);
    const bSort = Number(b.sort_order ?? 0);
    if (aSort !== bSort) return aSort - bSort;
    return getRewardCost(a) - getRewardCost(b);
  });
  if (adminRewardItems.length === 0) {
    list.className = "empty-state";
    list.textContent = "No rewards yet.";
    return;
  }

  list.className = "admin-rewards-list";
  list.innerHTML = adminRewardItems.map((item) => {
    const available = getRewardAvailableStock(item);
    const total = getRewardTotalStock(item);
    const reserved = getRewardReservedStock(item);
    return `
      <article class="admin-reward-row ${item.active ? "" : "inactive"}">
        <div class="admin-reward-thumb">
          ${getRewardImage(item) ? `<img src="${escapeHtml(getRewardImage(item))}" alt="" loading="lazy" />` : `<span>${shortSkinName(item.name || "")}</span>`}
        </div>
        <div>
          <strong>${escapeHtml(item.name)}</strong>
          <p class="muted">${getRewardCost(item).toLocaleString()} coins · ${escapeHtml(item.rarity || "No rarity")} · ${escapeHtml(item.condition || "No condition")}</p>
          <p class="muted">Stock: ${available ?? "∞"} available / ${total ?? "∞"} total / ${reserved} reserved · ${item.active ? "Active" : "Hidden"}</p>
        </div>
        <div class="admin-actions">
          <button class="button button-ghost" type="button" data-edit-reward="${item.id}">Edit</button>
          <button class="button button-ghost" type="button" data-toggle-reward="${item.id}">${item.active ? "Hide" : "Activate"}</button>
        </div>
      </article>
    `;
  }).join("");

  qsa("[data-edit-reward]").forEach((button) => {
    button.addEventListener("click", () => {
      const item = adminRewardItems.find((reward) => Number(reward.id) === Number(button.dataset.editReward));
      setRewardForm(item);
      qs("#adminRewardForm")?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  });

  qsa("[data-toggle-reward]").forEach((button) => {
    button.addEventListener("click", async () => {
      const item = adminRewardItems.find((reward) => Number(reward.id) === Number(button.dataset.toggleReward));
      if (!item) return;
      const { error } = await sb.from("reward_items").update({ active: !item.active }).eq("id", item.id);
      if (error) return showMessage(error.message);
      await loadAdminRewards();
    });
  });
}

async function refreshAll() {
  await updateNavAuthState();
  await updateHomeAuthState();
  await refreshDashboard();
  await refreshSettingsPage();
  await initOfferwall();
  await initAdmin();
}

async function boot() {
  initNav();
  initAuthModal();
  initSupportWidget();
  finishPageLoad();
  await updateNavAuthState();
  await updateHomeAuthState();
  await initAuthConfirmPage();
  await initOfferwall();

  if (qs("#rewardsGrid")) {
    try {
      await loadRewards();
      renderRewards();
      await updateRewardAccountNotice();
    } catch (error) {
      qs("#rewardsGrid").innerHTML = `<div class="empty-state">Could not load rewards right now. Please refresh and try again.</div>`;
    }
  }

  await initDashboard();
  await initSettingsPage();
  await initAdmin();
  finishPageLoad();
}

boot().catch((error) => {
  console.error(error);
  finishPageLoad();
});
