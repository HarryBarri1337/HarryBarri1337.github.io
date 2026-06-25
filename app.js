// SkinQuest v9.4 - email confirmation page, profile fallback, redeem diagnostics, admin coin tools.

const SUPABASE_URL = "https://ubvkupqgigfxehprsoit.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVidmt1cHFnaWdmeGVocHJzb2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4Nzc4NjIsImV4cCI6MjA5NzQ1Mzg2Mn0.GWI920G80kZYIOiFPvkHr-blpOvY_N-zvDY1QATCjfY";
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const ADMIN_EMAILS = ["harrygotesson@gmail.com"];
const CPX_APP_ID = 33831;

let rewardItems = [];
let adminRewardItems = [];
let currentUser = null;
let currentProfile = null;

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

  const close = () => {
    toast.classList.add("leaving");
    setTimeout(() => toast.remove(), 180);
  };

  toast.querySelector("button")?.addEventListener("click", close);
  setTimeout(close, Math.max(3200, Math.min(9000, String(message || "").length * 55)));
}

function showConfirm(message, options = {}) {
  return new Promise((resolve) => {
    const backdrop = document.createElement("div");
    backdrop.className = "confirm-backdrop";
    backdrop.innerHTML = `
      <div class="confirm-modal" role="dialog" aria-modal="true">
        <div class="confirm-icon ${options.danger ? "danger" : ""}">${options.icon || "SQ"}</div>
        <div class="confirm-copy">
          <h2>${escapeHtml(options.title || "Confirm action")}</h2>
          <p>${escapeHtml(message)}</p>
        </div>
        <div class="confirm-actions">
          <button class="button button-ghost" type="button" data-confirm-cancel>${escapeHtml(options.cancelText || "Cancel")}</button>
          <button class="button ${options.danger ? "button-danger" : "button-primary"}" type="button" data-confirm-ok>${escapeHtml(options.confirmText || "Confirm")}</button>
        </div>
      </div>
    `;

    const done = (value) => {
      backdrop.classList.add("leaving");
      setTimeout(() => backdrop.remove(), 160);
      resolve(value);
    };

    backdrop.addEventListener("click", (event) => {
      if (event.target === backdrop) done(false);
    });
    backdrop.querySelector("[data-confirm-cancel]")?.addEventListener("click", () => done(false));
    backdrop.querySelector("[data-confirm-ok]")?.addEventListener("click", () => done(true));
    document.body.appendChild(backdrop);
    backdrop.querySelector("[data-confirm-ok]")?.focus();
  });
}

function finishPageLoad() {
  const loader = qs("#pageLoader");
  if (!loader) return;
  setTimeout(() => loader.classList.add("done"), 180);
}

async function getSessionUser() {
  const { data, error } = await sb.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}

function isAdmin(user) {
  const email = (user?.email || "").toLowerCase();
  return ADMIN_EMAILS.includes(email);
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

  // v9.4 fallback: lets normal users get a profile even if direct insert RLS is too strict.
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
    .select("amount")
    .eq("user_id", userId);

  if (error || !data) return 0;
  return data.filter((row) => Number(row.amount) > 0).reduce((sum, row) => sum + Number(row.amount || 0), 0);
}

function calculateLevel(totalEarned) {
  return Math.max(1, Math.floor(Math.sqrt(Number(totalEarned || 0) / 1000)) + 1);
}

function xpForLevel(level) {
  return Math.pow(Math.max(0, level - 1), 2) * 1000;
}

function getLevelProgress(totalEarned) {
  const level = calculateLevel(totalEarned);
  const currentFloor = xpForLevel(level);
  const nextFloor = xpForLevel(level + 1);
  const progress = ((Number(totalEarned || 0) - currentFloor) / (nextFloor - currentFloor)) * 100;
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
  if (toggle && nav) {
    toggle.addEventListener("click", () => nav.classList.toggle("open"));
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
    showMessage("Google sign-in is not connected yet. Steam login can be added later.");
  });
}

async function updateNavAuthState() {
  const actions = qs("#navAuthActions");
  const user = await getSessionUser();
  currentUser = user;
  updateAdminVisibility(user);

  if (!actions) return;

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
  return item.image_url || item.image || item.icon_url || "";
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

function renderRewards() {
  const grid = qs("#rewardsGrid");
  if (!grid) return;

  const search = qs("#skinSearch");
  const filter = qs("#priceFilter");

  function apply() {
    const query = (search?.value || "").toLowerCase();
    const priceFilter = filter?.value || "all";

    const filtered = rewardItems.filter((item) => {
      const haystack = [item.name, item.description, item.rarity, item.condition, item.market_name].filter(Boolean).join(" ").toLowerCase();
      const cost = getRewardCost(item);
      const matchesSearch = haystack.includes(query);
      const matchesPrice =
        priceFilter === "all" ||
        (priceFilter === "low" && cost < 500) ||
        (priceFilter === "mid" && cost >= 500 && cost <= 1200) ||
        (priceFilter === "high" && cost > 1200);

      return matchesSearch && matchesPrice;
    });

    if (filtered.length === 0) {
      grid.innerHTML = `<div class="empty-state">No rewards found.</div>`;
      return;
    }

    grid.innerHTML = filtered.map((item) => {
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
      button.addEventListener("click", () => requestRedeem(Number(button.dataset.redeem)));
    });
  }

  search?.addEventListener("input", apply);
  filter?.addEventListener("change", apply);
  apply();
}

async function requestRedeem(rewardId) {
  const user = await getSessionUser();
  if (!user) {
    openAuthModal("signup");
    return;
  }

  let profile;
  try {
    profile = await ensureProfile(user);
  } catch (error) {
    showMessage(`Could not prepare your account profile: ${error.message}. Run the v9.4 Supabase patch if this happens for normal users.`, "error");
    return;
  }

  const reward = rewardItems.find((item) => Number(item.id) === Number(rewardId));
  if (!reward) return;

  if (!profile.steam_trade_url) {
    showMessage("Save your Steam trade URL on the Dashboard before redeeming.");
    location.href = "dashboard.html";
    return;
  }

  if (!isValidSteamTradeUrl(profile.steam_trade_url)) {
    showMessage("Your saved Steam trade URL looks invalid. Open Dashboard and save the correct trade offer link first.");
    location.href = "dashboard.html";
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

  const { error } = await sb.rpc("redeem_reward", { p_reward_id: rewardId });

  if (error) {
    return showMessage(`${error.message}\n\nIf this happens only for normal users, run skinquest_v9_4_supabase_patch.sql in Supabase.`, "error");
  }

  showMessage("Redeem request created. Coins were deducted and stock was reserved for manual review.", "success");
  await loadRewards();
  renderRewards();
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

      const { error } = await sb
        .from("profiles")
        .update({ steam_trade_url: steamTradeUrl })
        .eq("id", user.id);

      if (error) return showMessage(error.message);

      showMessage("Steam trade URL saved.");
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
  if (!authSection || !accountSection) return;

  const user = await getSessionUser();

  if (!user) {
    authSection.classList.remove("hidden");
    accountSection.classList.add("hidden");
    return;
  }

  authSection.classList.add("hidden");
  accountSection.classList.remove("hidden");

  const profile = await ensureProfile(user);
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
  setText("#xpDisplay", `${Number(totalEarned).toLocaleString()} XP`);
  setText("#levelText", `Level ${progress.level}`);
  setText("#nextLevelText", `${Number(progress.nextFloor - totalEarned).toLocaleString()} XP to Level ${progress.level + 1}`);

  const xpBar = qs("#xpBarFill");
  if (xpBar) xpBar.style.width = `${progress.progress}%`;

  const tradeUrl = qs("#tradeUrl");
  if (tradeUrl) tradeUrl.value = profile.steam_trade_url || "";

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

  redeemHistory.className = "redeem-list";
  redeemHistory.innerHTML = redemptions.map((item) => `
    <div class="redeem-row">
      <div>
        <strong>${escapeHtml(item.reward_name)}</strong>
        <p class="muted">${formatDate(item.created_at)} · ${getRequestCost(item).toLocaleString()} coins</p>
        ${item.trade_offer_url ? `<a class="mini-link" target="_blank" rel="noopener" href="${escapeHtml(item.trade_offer_url)}">Open trade offer</a>` : ""}
        ${item.admin_note ? `<p class="muted admin-note-view">${escapeHtml(item.admin_note)}</p>` : ""}
      </div>
      <span class="status-pill status-${escapeHtml(item.status)}">${escapeHtml(formatStatus(item.status))}</span>
    </div>
  `).join("");
}

async function renderCoinHistory(userId) {
  const coinHistory = qs("#coinHistory");
  if (!coinHistory) return;

  const { data, error } = await sb
    .from("coin_adjustments")
    .select("amount, reason, created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(20);

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

  coinHistory.className = "coin-history-list";
  coinHistory.innerHTML = data.map((item) => {
    const amount = Number(item.amount || 0);
    return `
      <div class="coin-history-row ${amount >= 0 ? "positive" : "negative"}">
        <strong>${amount >= 0 ? "+" : ""}${amount.toLocaleString()} coins</strong>
        <span>${escapeHtml(item.reason || "Coin adjustment")}</span>
        <small>${formatDate(item.created_at)}</small>
      </div>
    `;
  }).join("");
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

    if (error) return showMessage(`${error.message} Run skinquest_v9_4_supabase_patch.sql if the admin coin RPC is missing.`, "error");
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
    list.textContent = `${error.message} Run skinquest_v9_supabase_upgrade.sql if admin access/policies are missing.`;
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

  if (error) return showMessage(`${error.message}\n\nRun skinquest_v9_supabase_upgrade.sql if the admin RPC is missing.`);

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
  if (error) return showMessage(`${error.message}\n\nRun skinquest_v9_supabase_upgrade.sql if reward admin policies/columns are missing.`);

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
    list.textContent = `${error.message} Run skinquest_v9_supabase_upgrade.sql if admin reward access is missing.`;
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
  await initOfferwall();
  await initAdmin();
}

async function boot() {
  initNav();
  initAuthModal();
  await updateNavAuthState();
  await updateHomeAuthState();
  await initAuthConfirmPage();
  await initOfferwall();

  if (qs("#rewardsGrid")) {
    try {
      await loadRewards();
      renderRewards();
    } catch (error) {
      qs("#rewardsGrid").innerHTML = `<div class="empty-state">${escapeHtml(error.message)}<br><br>Run the v9 Supabase SQL if new reward columns are missing.</div>`;
    }
  }

  await initDashboard();
  await initAdmin();
  finishPageLoad();
}

boot().catch((error) => {
  console.error(error);
  finishPageLoad();
});
