// SkinQuest v8.1 - fixed auth buttons, CPX button, hover feel, and dashboard refresh.

const SUPABASE_URL = "https://ubvkupqgigfxehprsoit.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVidmt1cHFnaWdmeGVocHJzb2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4Nzc4NjIsImV4cCI6MjA5NzQ1Mzg2Mn0.GWI920G80kZYIOiFPvkHr-blpOvY_N-zvDY1QATCjfY";
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
const ADMIN_USER_IDS = ["6c4e7198-b08e-4e78-b4c7-f2abea9f5311"];
const CPX_APP_ID = 33831;

let currentUser = null;
let currentProfile = null;
let rewardItems = [];

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
  return new Date(value).toLocaleString();
}

function showMessage(message) {
  alert(message);
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

async function ensureProfile(user) {
  const { data: existing, error: selectError } = await sb
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  if (selectError) throw selectError;
  if (existing) return existing;

  const username = user.email ? user.email.split("@")[0] : "user";

  const { data: created, error: insertError } = await sb
    .from("profiles")
    .insert({ id: user.id, username })
    .select("*")
    .single();

  if (insertError) throw insertError;
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

    const { error } = await sb.auth.signUp({ email, password });
    if (error) return showMessage(error.message);

    showMessage("Account created. If email confirmation is enabled, check your inbox. Then sign in.");
    setAuthMode("login");
  });

  qs("#modalLoginForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();

    const email = qs("#modalLoginEmail")?.value.trim();
    const password = qs("#modalLoginPassword")?.value;

    const { error } = await sb.auth.signInWithPassword({ email, password });
    if (error) return showMessage(error.message);

    closeAuthModal();
    await refreshAll();
  });

  qs("#googleLoginButton")?.addEventListener("click", () => {
    showMessage("Google sign-in is not connected yet. We'll add it next.");
  });
}

async function updateNavAuthState() {
  const actions = qs("#navAuthActions");
  if (!actions) return;

  const user = await getSessionUser();

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
    coins = Number(profile.points_balance || 0);
  } catch {}

  actions.innerHTML = `
    <a class="coin-pill" href="dashboard.html">🪙 ${coins.toLocaleString()} coins</a>
    <a class="nav-login nav-clickable" href="dashboard.html">Account</a>
    <button class="button button-ghost nav-cta" type="button" id="navLogoutButton">Log out</button>
  `;

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
    if (homePending) homePending.textContent = (redemptions || []).filter((item) => item.status === "pending").length;
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
  const { data, error } = await sb
    .from("reward_items")
    .select("*")
    .eq("active", true)
    .order("points_cost", { ascending: true });

  if (error) throw error;
  rewardItems = data || [];
}

function getRewardRarity(item) {
  const name = (item.name || "").toLowerCase();

  if (name.includes("sand dune")) return { key: "consumer", label: "Consumer" };
  if (name.includes("moonrise")) return { key: "restricted", label: "Restricted" };
  if (name.includes("ticket to hell")) return { key: "restricted", label: "Restricted" };
  if (name.includes("slate")) return { key: "restricted", label: "Restricted" };
  if (name.includes("night terror")) return { key: "restricted", label: "Restricted" };
  if (name.includes("atheris")) return { key: "restricted", label: "Restricted" };

  return { key: "milspec", label: "Mil-Spec" };
}

function rarityClass(item) {
  return `rarity-${getRewardRarity(item).key}`;
}

function shortSkinName(name) {
  if (name.includes("AK-47")) return "AK";
  if (name.includes("AWP")) return "AWP";
  if (name.includes("M4")) return "M4";
  if (name.includes("USP")) return "USP";
  if (name.includes("Glock")) return "G18";
  if (name.includes("P250")) return "P250";
  return "CS";
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
      const matchesSearch = item.name.toLowerCase().includes(query);
      const matchesPrice =
        priceFilter === "all" ||
        (priceFilter === "low" && item.points_cost < 500) ||
        (priceFilter === "mid" && item.points_cost >= 500 && item.points_cost <= 1200) ||
        (priceFilter === "high" && item.points_cost > 1200);

      return matchesSearch && matchesPrice;
    });

    if (filtered.length === 0) {
      grid.innerHTML = `<div class="empty-state">No rewards found.</div>`;
      return;
    }

    grid.innerHTML = filtered.map((item) => {
      const rarity = getRewardRarity(item);
      return `
        <article class="reward-card steam-item ${rarityClass(item)}">
          <div class="reward-art"><span class="skin-abbrev">${shortSkinName(item.name)}</span></div>
          <div class="reward-info">
            <div class="reward-title-row">
              <span class="rarity-badge">${rarity.label}</span>
              <span class="condition-badge">FT</span>
            </div>
            <h2>${escapeHtml(item.name)}</h2>
            <p class="muted">Manual Steam trade after review</p>
            <div class="reward-meta">
              <span class="price">🪙 ${Number(item.points_cost).toLocaleString()} coins</span>
            </div>
            <div class="reward-actions">
              <button class="button button-primary" type="button" data-redeem="${item.id}">Redeem</button>
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

  const profile = await ensureProfile(user);
  const reward = rewardItems.find((item) => item.id === rewardId);
  if (!reward) return;

  if (!profile.steam_trade_url) {
    showMessage("Save your Steam trade URL on the Dashboard before redeeming.");
    location.href = "dashboard.html";
    return;
  }

  if (profile.points_balance < reward.points_cost) {
    showMessage("Not enough coins yet.");
    return;
  }

  if (!confirm(`Redeem ${reward.name} for ${reward.points_cost} coins? Coins will be deducted immediately while pending.`)) return;

  const newBalance = profile.points_balance - reward.points_cost;

  const { error: updateError } = await sb
    .from("profiles")
    .update({ points_balance: newBalance })
    .eq("id", user.id);

  if (updateError) return showMessage(updateError.message);

  const { error: redeemError } = await sb.from("redemption_requests").insert({
    user_id: user.id,
    reward_item_id: reward.id,
    reward_name: reward.name,
    points_cost: reward.points_cost,
    steam_trade_url: profile.steam_trade_url,
    status: "pending"
  });

  if (redeemError) {
    await sb.from("profiles").update({ points_balance: profile.points_balance }).eq("id", user.id);
    return showMessage(redeemError.message);
  }

  await sb.from("coin_adjustments").insert({
    user_id: user.id,
    amount: -reward.points_cost,
    reason: `Redeem pending / ${reward.name}`
  });

  showMessage("Redeem request created. Coins were deducted and the request is now pending review.");
  await refreshAll();
}

async function initDashboard() {
  const tradeForm = qs("#tradeForm");
  if (tradeForm) {
    tradeForm.addEventListener("submit", async (event) => {
      event.preventDefault();

      const user = await getSessionUser();
      if (!user) return openAuthModal("login");

      const steamTradeUrl = qs("#tradeUrl")?.value.trim();

      const { error } = await sb
        .from("profiles")
        .update({ steam_trade_url: steamTradeUrl })
        .eq("id", user.id);

      if (error) return showMessage(error.message);

      showMessage("Steam trade URL saved.");
      await refreshAll();
    });
  }

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

  if (error) return;

  setText("#pendingDisplay", (redemptions || []).filter((item) => item.status === "pending").length);

  const redeemHistory = qs("#redeemHistory");
  if (!redeemHistory) return;

  if (!redemptions || redemptions.length === 0) {
    redeemHistory.className = "empty-state";
    redeemHistory.innerHTML = "No redeem history yet.";
    return;
  }

  redeemHistory.className = "";
  redeemHistory.innerHTML = redemptions.map((item) => `
    <div class="redeem-row">
      <div>
        <strong>${escapeHtml(item.reward_name)}</strong>
        <p class="muted">${formatDate(item.created_at)} · ${item.points_cost} coins</p>
      </div>
      <span class="status-pill status-${escapeHtml(item.status)}">${escapeHtml(item.status)}</span>
    </div>
  `).join("");
}

function isAdmin(user) {
  return !!user && ADMIN_USER_IDS.includes(user.id);
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

  qs("#refreshAdmin")?.addEventListener("click", loadAdminRequests);
  await loadAdminRequests();
}

async function loadAdminRequests() {
  const list = qs("#adminRequests");
  if (!list) return;

  const { data, error } = await sb
    .from("redemption_requests")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    list.className = "empty-state";
    list.textContent = error.message;
    return;
  }

  if (!data || data.length === 0) {
    list.className = "empty-state";
    list.textContent = "No redeem requests yet.";
    return;
  }

  list.className = "admin-list";
  list.innerHTML = data.map((item) => `
    <article class="admin-request">
      <div>
        <strong>${escapeHtml(item.reward_name)}</strong>
        <p class="muted">${formatDate(item.created_at)} · ${item.points_cost} coins</p>
        <p class="admin-url">${escapeHtml(item.steam_trade_url)}</p>
      </div>
      <div class="admin-actions">
        <span class="status-pill status-${escapeHtml(item.status)}">${escapeHtml(item.status)}</span>
        <button class="button button-ghost" type="button" data-admin-status="completed" data-request-id="${item.id}">Mark completed</button>
        <button class="button button-ghost" type="button" data-admin-status="rejected" data-request-id="${item.id}">Reject</button>
      </div>
    </article>
  `).join("");

  qsa("[data-admin-status]").forEach((button) => {
    button.addEventListener("click", () => updateRedeemStatus(Number(button.dataset.requestId), button.dataset.adminStatus));
  });
}

async function updateRedeemStatus(id, status) {
  const { error } = await sb
    .from("redemption_requests")
    .update({ status })
    .eq("id", id);

  if (error) return showMessage(error.message);

  showMessage(`Request marked ${status}.`);
  await loadAdminRequests();
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
  await initOfferwall();

  if (qs("#rewardsGrid")) {
    try {
      await loadRewards();
      renderRewards();
    } catch (error) {
      qs("#rewardsGrid").innerHTML = `<div class="empty-state">${escapeHtml(error.message)}</div>`;
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
