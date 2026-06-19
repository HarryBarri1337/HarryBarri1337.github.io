// SkinQuest v3 - Supabase-connected frontend.
// Safe to expose the anon public key in frontend when Row Level Security is enabled.
// NEVER put the service_role key in frontend code.

const SUPABASE_URL = "https://ubvkupqgigfxehprsoit.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVidmt1cHFnaWdmeGVocHJzb2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4Nzc4NjIsImV4cCI6MjA5NzQ1Mzg2Mn0.GWI920G80kZYIOiFPvkHr-blpOvY_N-zvDY1QATCjfY";
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const OFFERWALL_URL = "https://example.com/offerwall?user_id=";
// Replace later with your real offerwall URL after publisher approval.

let currentUser = null;
let currentProfile = null;
let rewardItems = [];

function qs(selector) {
  return document.querySelector(selector);
}

function qsa(selector) {
  return Array.from(document.querySelectorAll(selector));
}

function formatDate(value) {
  return new Date(value).toLocaleString();
}

function showMessage(message) {
  alert(message);
}

function initNav() {
  const toggle = qs("[data-nav-toggle]");
  const nav = qs("[data-nav]");
  if (!toggle || !nav) return;

  toggle.addEventListener("click", () => {
    nav.classList.toggle("open");
  });

  const current = location.pathname.split("/").pop() || "index.html";
  nav.querySelectorAll("a").forEach((link) => {
    if (link.getAttribute("href") === current) link.classList.add("active");
  });
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
    .insert({
      id: user.id,
      username
    })
    .select("*")
    .single();

  if (insertError) throw insertError;
  return created;
}

async function loadProfile() {
  currentUser = await getSessionUser();
  if (!currentUser) return null;

  currentProfile = await ensureProfile(currentUser);
  return currentProfile;
}

async function initOfferwall() {
  const button = qs("#openOfferwall");
  if (!button) return;

  button.addEventListener("click", async () => {
    const user = await getSessionUser();
    if (!user) {
      showMessage("Log in on the Dashboard first.");
      location.href = "dashboard.html";
      return;
    }

    if (OFFERWALL_URL.includes("example.com")) {
      showMessage("Offerwall URL is not connected yet. We need provider approval first.");
      return;
    }

    window.open(OFFERWALL_URL + encodeURIComponent(user.id), "_blank");
  });
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

    grid.innerHTML = filtered.map((item) => `
      <article class="reward-card">
        <div class="reward-art">${shortSkinName(item.name)}</div>
        <div class="reward-info">
          <h2>${escapeHtml(item.name)}</h2>
          <p class="muted">CS2 reward</p>
          <div class="reward-meta">
            <span class="price">${item.points_cost} pts</span>
          </div>
          <div class="reward-actions">
            <button class="button button-primary" data-redeem="${item.id}">Request redeem</button>
          </div>
        </div>
      </article>
    `).join("");

    qsa("[data-redeem]").forEach((button) => {
      button.addEventListener("click", () => requestRedeem(Number(button.dataset.redeem)));
    });
  }

  search?.addEventListener("input", apply);
  filter?.addEventListener("change", apply);
  apply();
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

async function requestRedeem(rewardId) {
  const user = await getSessionUser();
  if (!user) {
    showMessage("Log in on the Dashboard first.");
    location.href = "dashboard.html";
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
    showMessage("Not enough points yet.");
    return;
  }

  // This creates a pending request only.
  // A real backend/admin process should verify balance and deduct points server-side.
  const { error } = await sb.from("redemption_requests").insert({
    user_id: user.id,
    reward_item_id: reward.id,
    reward_name: reward.name,
    points_cost: reward.points_cost,
    steam_trade_url: profile.steam_trade_url
  });

  if (error) {
    showMessage(error.message);
    return;
  }

  showMessage("Redeem request created. It now needs manual review.");
}

async function initDashboard() {
  const authSection = qs("#authSection");
  const accountSection = qs("#accountSection");
  const signupForm = qs("#signupForm");
  const loginForm = qs("#loginForm");
  const logoutButton = qs("#logoutButton");

  if (!authSection || !accountSection) return;

  signupForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const email = qs("#signupEmail").value.trim();
    const password = qs("#signupPassword").value;

    const { data, error } = await sb.auth.signUp({ email, password });
    if (error) {
      showMessage(error.message);
      return;
    }

    showMessage("Account created. If email confirmation is enabled, check your inbox. Then log in.");
  });

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const email = qs("#loginEmail").value.trim();
    const password = qs("#loginPassword").value;

    const { error } = await sb.auth.signInWithPassword({ email, password });
    if (error) {
      showMessage(error.message);
      return;
    }

    await refreshDashboard();
  });

  logoutButton.addEventListener("click", async () => {
    await sb.auth.signOut();
    await refreshDashboard();
  });

  const tradeForm = qs("#tradeForm");
  tradeForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const user = await getSessionUser();
    if (!user) return;

    const steamTradeUrl = qs("#tradeUrl").value.trim();

    const { error } = await sb
      .from("profiles")
      .update({ steam_trade_url: steamTradeUrl })
      .eq("id", user.id);

    if (error) {
      showMessage(error.message);
      return;
    }

    showMessage("Steam trade URL saved.");
    await refreshDashboard();
  });

  await refreshDashboard();
}

async function refreshDashboard() {
  const authSection = qs("#authSection");
  const accountSection = qs("#accountSection");
  const accountEmail = qs("#accountEmail");
  const balanceDisplay = qs("#balanceDisplay");
  const pendingDisplay = qs("#pendingDisplay");
  const userIdDisplay = qs("#userIdDisplay");
  const tradeUrl = qs("#tradeUrl");
  const redeemHistory = qs("#redeemHistory");

  const user = await getSessionUser();

  if (!user) {
    authSection.classList.remove("hidden");
    accountSection.classList.add("hidden");
    return;
  }

  authSection.classList.add("hidden");
  accountSection.classList.remove("hidden");

  const profile = await ensureProfile(user);

  accountEmail.textContent = user.email || "Unknown";
  balanceDisplay.textContent = profile.points_balance || 0;
  userIdDisplay.textContent = user.id.slice(0, 8);
  tradeUrl.value = profile.steam_trade_url || "";

  const { data: redemptions, error } = await sb
    .from("redemption_requests")
    .select("*")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  if (error) {
    redeemHistory.textContent = error.message;
    return;
  }

  pendingDisplay.textContent = (redemptions || []).filter((item) => item.status === "pending").length;

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
        <p class="muted">${formatDate(item.created_at)} · ${item.points_cost} pts</p>
      </div>
      <span class="status-pill">${escapeHtml(item.status)}</span>
    </div>
  `).join("");
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

async function boot() {
  initNav();
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
}

boot();
