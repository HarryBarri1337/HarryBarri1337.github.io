// SkinQuest v12.1.2 - PWA install support and goal rewards (star + track + claim).

const SUPABASE_URL = "https://ubvkupqgigfxehprsoit.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVidmt1cHFnaWdmeGVocHJzb2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4Nzc4NjIsImV4cCI6MjA5NzQ1Mzg2Mn0.GWI920G80kZYIOiFPvkHr-blpOvY_N-zvDY1QATCjfY";
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

const ADMIN_EMAILS = []; // v11.6: admin access must come from Supabase admin_users via is_admin().
const CPX_APP_ID = 33831;
const SUPPORT_EMAIL = "support@skinquestcs.com"; // Public support contact. Form requests are saved to Supabase and can trigger server-side email notifications.
const STEAM_AUTH_START_URL = `${SUPABASE_URL}/functions/v1/steam-auth-start`;
const STEAM_AUTH_DISCONNECT_URL = `${SUPABASE_URL}/functions/v1/steam-disconnect`;

const SITE_THEMES = {
  nuke: { label: "Nuke", status: "Cold blue" },
  train: { label: "Train", status: "Industrial" },
  mirage: { label: "Mirage", status: "Desert" },
  dust2: { label: "Dust2", status: "Classic" },
  ancient: { label: "Ancient", status: "Jungle" }
};
const DEFAULT_SITE_THEME = "nuke";
const SITE_THEME_STORAGE_KEY = "skinquest.siteTheme";
const NAV_AUTH_CACHE_KEY = "skinquest.navAuthCache";

function getSavedSiteTheme() {
  try {
    const saved = localStorage.getItem(SITE_THEME_STORAGE_KEY);
    return SITE_THEMES[saved] ? saved : DEFAULT_SITE_THEME;
  } catch {
    return DEFAULT_SITE_THEME;
  }
}

function applySiteTheme(themeKey, options = {}) {
  const key = SITE_THEMES[themeKey] ? themeKey : DEFAULT_SITE_THEME;
  document.documentElement.dataset.theme = key;
  qsa("[data-theme-option]").forEach((button) => {
    const isActive = button.dataset.themeOption === key;
    button.classList.toggle("active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
    const badge = button.querySelector("span");
    if (badge) badge.textContent = isActive ? "Current" : SITE_THEMES[button.dataset.themeOption]?.status || "Available";
  });
  if (options.persist) {
    try { localStorage.setItem(SITE_THEME_STORAGE_KEY, key); } catch {}
    showMessage(`${SITE_THEMES[key].label} theme applied.`, "success");
  }
  return key;
}

function initThemeControls() {
  applySiteTheme(getSavedSiteTheme());
  qsa("[data-theme-option]").forEach((button) => {
    button.addEventListener("click", () => applySiteTheme(button.dataset.themeOption, { persist: true }));
  });
}

applySiteTheme(getSavedSiteTheme());

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  });
}

let rewardItems = [];
let adminRewardItems = [];
let currentUser = null;
let currentProfile = null;
let currentIsAdmin = false;
let currentAdminRole = null;
let favoriteRewardIds = new Set();
const MAX_FAVORITE_REWARDS = 5;

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

function isValidEmailAddress(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/i.test(String(value || "").trim());
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
  if (isSteamOnlyEmail(email)) return "Steam account";
  const [name, domain] = String(email).split("@");
  if (!domain) return email;
  return `${name}@${domain}`;
}

function isSteamOnlyEmail(email) {
  return String(email || "").toLowerCase().endsWith("@steam.skinquestcs.com");
}

function displayAccountEmail(user, profile = null) {
  if (isSteamOnlyEmail(user?.email)) {
    return profile?.steam_name || profile?.username || "Steam account";
  }
  return user?.email || "Account";
}

function copyToClipboard(value, successMessage = "Copied.") {
  const text = String(value || "").trim();
  if (!text) {
    showMessage("Nothing to copy yet.", "error");
    return Promise.resolve(false);
  }

  if (navigator.clipboard?.writeText) {
    return navigator.clipboard.writeText(text)
      .then(() => { showMessage(successMessage, "success"); return true; })
      .catch(() => legacyCopyToClipboard(text, successMessage));
  }

  return Promise.resolve(legacyCopyToClipboard(text, successMessage));
}

function legacyCopyToClipboard(text, successMessage) {
  const input = document.createElement("textarea");
  input.value = text;
  input.setAttribute("readonly", "");
  input.style.position = "fixed";
  input.style.opacity = "0";
  document.body.appendChild(input);
  input.select();
  let copied = false;
  try { copied = document.execCommand("copy"); } catch {}
  input.remove();
  showMessage(copied ? successMessage : "Could not copy automatically. Select and copy manually.", copied ? "success" : "error");
  return copied;
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


function setButtonBusy(button, busyText = "Saving...") {
  if (!button) return () => {};
  if (!button.dataset.defaultText) button.dataset.defaultText = button.textContent.trim();
  const original = button.dataset.defaultText || button.textContent.trim();
  button.disabled = true;
  button.classList.add("is-saving");
  button.textContent = busyText;
  return () => {
    button.disabled = false;
    button.classList.remove("is-saving");
    button.textContent = original;
  };
}

function flashButtonSaved(button, savedText = "Saved") {
  if (!button) return;
  const original = button.dataset.defaultText || button.textContent.trim();
  button.disabled = true;
  button.classList.remove("is-saving");
  button.classList.add("is-saved");
  button.textContent = savedText;
  setTimeout(() => {
    button.disabled = false;
    button.classList.remove("is-saved");
    button.textContent = original;
  }, 1200);
}

function getSteamEmailPromptSnoozeKey(userId) {
  return `skinquest_steam_email_prompt_snooze_${userId}`;
}

function shouldShowSteamEmailPrompt(user) {
  if (!user?.id || !isSteamOnlyEmail(user.email)) return false;
  const snoozedUntil = Number(localStorage.getItem(getSteamEmailPromptSnoozeKey(user.id)) || 0);
  return Date.now() > snoozedUntil;
}

async function showSteamEmailPrompt(user) {
  if (!user?.id || !isSteamOnlyEmail(user.email)) return;
  if (document.querySelector(".email-prompt-backdrop")) return;

  const backdrop = document.createElement("div");
  backdrop.className = "confirm-backdrop email-prompt-backdrop";
  backdrop.innerHTML = `
    <div class="confirm-modal email-prompt-modal" role="dialog" aria-modal="true" aria-labelledby="steamEmailPromptTitle">
      <div class="confirm-icon">@</div>
      <div class="confirm-copy">
        <h2 id="steamEmailPromptTitle">Add your email</h2>
        <p>Steam does not share your real email. Add one so SkinQuest can send reward updates and account notifications.</p>
      </div>
      <form class="email-prompt-form" id="steamEmailPromptForm">
        <label class="input-label">Email address
          <input id="steamEmailPromptInput" type="email" placeholder="you@example.com" autocomplete="email" required />
        </label>
        <p class="fine-print">We will send the normal Supabase confirmation email. Your address is active after you confirm it.</p>
        <div class="confirm-actions">
          <button class="button button-ghost" type="button" data-email-prompt-later>Later</button>
          <button class="button button-primary" type="submit" data-email-prompt-save>Send confirmation</button>
        </div>
      </form>
    </div>
  `;

  const close = (snooze = true) => {
    if (snooze) {
      localStorage.setItem(getSteamEmailPromptSnoozeKey(user.id), String(Date.now() + 12 * 60 * 60 * 1000));
    }
    backdrop.classList.remove("show");
    backdrop.classList.add("leaving");
    setTimeout(() => backdrop.remove(), 220);
  };

  backdrop.addEventListener("click", (event) => {
    if (event.target === backdrop) close(true);
  });
  backdrop.querySelector("[data-email-prompt-later]")?.addEventListener("click", () => close(true));
  backdrop.querySelector("#steamEmailPromptForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const input = backdrop.querySelector("#steamEmailPromptInput");
    const saveButton = backdrop.querySelector("[data-email-prompt-save]");
    const email = input?.value.trim().toLowerCase();
    if (!email || !isValidEmailAddress(email)) {
      showMessage("Enter a valid email address.", "error");
      input?.focus();
      return;
    }
    const reset = setButtonBusy(saveButton, "Sending...");
    const { error } = await sb.auth.updateUser(
      { email },
      { emailRedirectTo: getPageUrl("auth-confirm.html") }
    );
    reset();
    if (error) {
      showMessage(error.message || "Could not send confirmation email.", "error");
      return;
    }
    localStorage.removeItem(getSteamEmailPromptSnoozeKey(user.id));
    showMessage("Confirmation email sent. Open it to finish adding your email.", "success");
    close(false);
  });

  document.body.appendChild(backdrop);
  requestAnimationFrame(() => backdrop.classList.add("show"));
  setTimeout(() => backdrop.querySelector("#steamEmailPromptInput")?.focus(), 120);
}

async function confirmAndSignOut() {
  const confirmed = await showConfirm("Are you sure you want to log out of SkinQuest?", {
    title: "Log out?",
    confirmText: "Log out",
    cancelText: "Stay signed in",
    icon: "↪",
    danger: true
  });
  if (!confirmed) return;
  await sb.auth.signOut();
  setCachedNavAuthState(null);
  location.href = "index.html";
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

function isOwner(user = currentUser) {
  return !!user?.id && String(currentAdminRole || "").toLowerCase() === "owner";
}

async function fetchAdminRole(user) {
  if (!user?.id) return null;

  try {
    const { data, error } = await sb.rpc("get_admin_role");
    if (!error && data) return String(data);
  } catch (error) {
    console.warn("Admin role check failed:", error);
  }

  try {
    const { data, error } = await sb.rpc("is_admin");
    if (!error && data === true) return "admin";
  } catch (error) {
    console.warn("Fallback admin status check failed:", error);
  }

  return null;
}

async function fetchAdminStatus(user) {
  currentAdminRole = await fetchAdminRole(user);
  return !!currentAdminRole;
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

    const noNewIdentity = data?.user && Array.isArray(data.user.identities) && data.user.identities.length === 0;
    if (noNewIdentity) {
      showMessage("This email may already have a SkinQuest account. Try signing in instead.", "error");
    } else {
      showMessage("Check your inbox for a confirmation link. If you already have an account, use Sign in instead.", "success");
    }
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
    showMessage("Google sign-in is planned for version 12. Use email sign-in for now.");
  });

  qs("#steamLoginButton")?.addEventListener("click", startSteamAuthFromModal);
}


function getCachedNavAuthState() {
  try {
    const cached = JSON.parse(localStorage.getItem(NAV_AUTH_CACHE_KEY) || "null");
    if (!cached || cached.expiresAt < Date.now()) return null;
    return cached;
  } catch {
    return null;
  }
}

function setCachedNavAuthState(data) {
  try {
    if (!data) {
      localStorage.removeItem(NAV_AUTH_CACHE_KEY);
      return;
    }
    localStorage.setItem(NAV_AUTH_CACHE_KEY, JSON.stringify({
      ...data,
      expiresAt: Date.now() + 1000 * 60 * 30
    }));
  } catch {}
}

function renderSignedOutNav(actions) {
  if (!actions) return;
  actions.innerHTML = `
    <button class="nav-login nav-clickable" type="button" data-open-auth="login">Sign in</button>
    <button class="button button-primary nav-cta" type="button" data-open-auth="signup">Sign up</button>
  `;
}

function renderSignedInNav(actions, { user, email, coins = 0, navLevel = null, adminLink = "", currentAdminRole = "" }) {
  if (!actions || !user) return;
  const levelText = navLevel ? `Lvl ${navLevel.level}` : "Lvl —";
  const levelProgress = navLevel ? navLevel.progress : 0;
  const safeEmail = email || displayAccountEmail(user, currentProfile);
  const levelPill = `
    <a class="level-pill" href="dashboard.html" aria-label="${escapeHtml(levelText)} progress">
      <span class="level-pill-label">${escapeHtml(levelText)}</span>
      <span class="level-pill-track"><span style="width:${levelProgress}%"></span></span>
    </a>
  `;

  actions.innerHTML = `
    <a class="coin-pill" href="dashboard.html" aria-label="Your coin balance">
      ${coinIcon("coin-icon-small")}
      <strong>${Number(coins || 0).toLocaleString()}</strong>
      <span>coins</span>
    </a>
    ${levelPill}
    <div class="account-menu" data-account-menu>
      <button class="account-trigger" type="button" id="accountMenuButton" aria-haspopup="true" aria-expanded="false">
        <span class="account-avatar">${escapeHtml(userInitial(user))}</span>
        <span class="account-trigger-copy">
          <strong>${escapeHtml(safeEmail.split("@")[0] || "Account")}</strong>
        </span>
        <span class="account-chevron">⌄</span>
      </button>
      <div class="account-dropdown hidden" id="accountDropdown" role="menu">
        <div class="account-dropdown-head">
          <span class="account-avatar large">${escapeHtml(userInitial(user))}</span>
          <div>
            <strong>${escapeHtml(safeEmail)}</strong>
            <small>${Number(coins || 0).toLocaleString()} coins${currentAdminRole ? ` · ${escapeHtml(currentAdminRole)}` : ""}</small>
          </div>
        </div>
        <a href="dashboard.html">Dashboard</a>
        <a href="settings.html">Settings</a>
        <a href="rewards.html">Rewards</a>
        <a href="earn.html">Surveys</a>
        ${adminLink}
        <button type="button" id="navLogoutButton">Log out</button>
      </div>
    </div>
  `;

  bindAccountMenu();
}

function bindAccountMenu() {
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

  qs("#navLogoutButton")?.addEventListener("click", confirmAndSignOut);
}

async function updateNavAuthState() {
  const actions = qs("#navAuthActions");
  const cached = actions ? getCachedNavAuthState() : null;
  if (actions && cached?.user) {
    renderSignedInNav(actions, {
      user: cached.user,
      email: cached.email,
      coins: cached.coins,
      navLevel: cached.navLevel,
      adminLink: cached.isAdmin ? `<a href="admin.html">${escapeHtml(cached.adminLabel || "Admin panel")}</a>` : "",
      currentAdminRole: cached.currentAdminRole || ""
    });
    actions.classList.remove("auth-loading");
    actions.classList.add("nav-restored");
  }

  const user = await getSessionUser();
  currentUser = user;
  currentIsAdmin = await fetchAdminStatus(user);
  updateAdminVisibility(user);

  if (!actions) return;

  if (!user) {
    setCachedNavAuthState(null);
    actions.classList.remove("auth-loading", "nav-restored");
    renderSignedOutNav(actions);
    return;
  }

  let coins = 0;
  let navLevel = null;
  try {
    const profile = await ensureProfile(user);
    currentProfile = profile;
    coins = Number(profile.points_balance || 0);
    const totalEarned = await getTotalEarned(user.id);
    navLevel = getLevelProgress(totalEarned);
  } catch {}

  const email = displayAccountEmail(user, currentProfile);
  const adminLabel = isOwner(user) ? "Owner panel" : "Admin panel";
  const adminLink = isAdmin(user) ? `<a href="admin.html">${escapeHtml(adminLabel)}</a>` : "";

  actions.classList.remove("auth-loading", "nav-restored");
  renderSignedInNav(actions, { user, email, coins, navLevel, adminLink, currentAdminRole: isAdmin(user) ? currentAdminRole : "" });
  setCachedNavAuthState({
    user: { id: user.id, email: user.email, user_metadata: user.user_metadata || {} },
    email,
    coins,
    navLevel,
    isAdmin: isAdmin(user),
    adminLabel,
    currentAdminRole: isAdmin(user) ? currentAdminRole : ""
  });
}

async function updateHomeAuthState() {
  const guest = qs("[data-guest-home]");
  const authed = qs("[data-user-home]");
  if (!guest || !authed) return;

  const setHomeStats = (coins = "—", level = "—", pending = "—") => {
    const homeCoins = qs("[data-home-coins]");
    const homeLevel = qs("[data-home-level]");
    const homePending = qs("[data-home-pending]");
    if (homeCoins) homeCoins.textContent = coins;
    if (homeLevel) homeLevel.textContent = level;
    if (homePending) homePending.textContent = pending;
  };

  setHomeStats();
  const user = await getSessionUser();

  if (!user) {
    guest.classList.remove("hidden");
    authed.classList.add("hidden");
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

    setHomeStats(
      Number(profile.points_balance || 0).toLocaleString(),
      String(calculateLevel(totalEarned)),
      String((redemptions || []).filter((item) => ["pending", "reviewing", "trade_sent"].includes(item.status)).length)
    );
  } catch {
    setHomeStats();
  }
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

async function loadFavoriteRewards(userId) {
  if (!userId) {
    favoriteRewardIds = new Set();
    return favoriteRewardIds;
  }

  const { data, error } = await sb.from("favorite_rewards").select("reward_id").eq("user_id", userId);
  favoriteRewardIds = new Set(error ? [] : (data || []).map((row) => Number(row.reward_id)));
  return favoriteRewardIds;
}

function updateFavoriteCountUi() {
  qsa("[data-favorite-count]").forEach((el) => {
    el.textContent = `${favoriteRewardIds.size}/${MAX_FAVORITE_REWARDS} goals starred`;
  });
}

async function toggleFavoriteReward(rewardId, starButton = null) {
  const user = await getSessionUser();
  if (!user) {
    openAuthModal("login");
    return;
  }

  const id = Number(rewardId);
  const isFavorited = favoriteRewardIds.has(id);

  if (!isFavorited && favoriteRewardIds.size >= MAX_FAVORITE_REWARDS) {
    showMessage(`You can only star up to ${MAX_FAVORITE_REWARDS} rewards as goals. Unstar one first.`, "error");
    return;
  }

  starButton?.classList.add("is-busy");

  if (isFavorited) {
    const { error } = await sb.from("favorite_rewards").delete().eq("user_id", user.id).eq("reward_id", id);
    starButton?.classList.remove("is-busy");
    if (error) return showMessage("Could not remove that goal. Please try again.", "error");
    favoriteRewardIds.delete(id);
  } else {
    const { error } = await sb.from("favorite_rewards").insert({ user_id: user.id, reward_id: id });
    starButton?.classList.remove("is-busy");
    if (error) {
      const friendly = /favou?rite/i.test(error.message || "") ? error.message : "Could not star that reward. Please try again.";
      showMessage(friendly, "error");
      return;
    }
    favoriteRewardIds.add(id);
  }

  qsa(`[data-favorite-star="${id}"]`).forEach((button) => {
    button.classList.toggle("is-favorited", favoriteRewardIds.has(id));
    button.setAttribute("aria-pressed", String(favoriteRewardIds.has(id)));
    button.setAttribute("aria-label", favoriteRewardIds.has(id) ? "Remove goal star" : "Set as goal");
  });
  updateFavoriteCountUi();
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

function getRewardActionState(item, profile) {
  const cost = getRewardCost(item);
  const balance = Number(profile?.points_balance || 0);
  const hasUser = !!currentUser?.id;
  const tradeUrl = profile?.steam_trade_url || "";
  const hasTrade = !!tradeUrl && isValidSteamTradeUrl(tradeUrl);

  if (rewardIsOutOfStock(item)) {
    return { disabled: true, label: "Out of stock", note: "This reward is currently unavailable.", action: "out" };
  }
  if (!hasUser) {
    return { disabled: false, label: "Sign in to redeem", note: "Create an account before redeeming.", action: "login" };
  }
  if (!hasTrade) {
    return { disabled: false, label: "Add trade URL", note: "Save your Steam trade URL once to unlock redeeming.", action: "trade" };
  }
  if (balance < cost) {
    const missing = Math.max(0, cost - balance);
    return { disabled: false, label: "Complete surveys", note: `Need ${missing.toLocaleString()} more coins`, action: "earn" };
  }
  return { disabled: false, label: "Redeem", note: "Manual review after request.", action: "redeem" };
}

const REWARD_SHOP_PREFS_KEY = "skinquest_reward_shop_preferences";
const REWARD_SORT_LABELS = {
  "price-desc": "Price: high to low",
  "price-asc": "Price: low to high",
  featured: "Featured",
  "stock-desc": "Most stock first",
  "name-asc": "Name: A to Z"
};

function getRewardShopPreferences() {
  const defaults = {
    default_sort: "price-desc",
    show_out_of_stock: true,
    compact_cards: false
  };
  try {
    const stored = JSON.parse(localStorage.getItem(REWARD_SHOP_PREFS_KEY) || "{}");
    const merged = { ...defaults, ...stored };
    if (!REWARD_SORT_LABELS[merged.default_sort]) merged.default_sort = defaults.default_sort;
    merged.show_out_of_stock = merged.show_out_of_stock !== false;
    merged.compact_cards = !!merged.compact_cards;
    return merged;
  } catch {
    return defaults;
  }
}

function saveRewardShopPreferences(partial) {
  const next = { ...getRewardShopPreferences(), ...partial };
  if (!REWARD_SORT_LABELS[next.default_sort]) next.default_sort = "price-desc";
  localStorage.setItem(REWARD_SHOP_PREFS_KEY, JSON.stringify(next));
  applyRewardShopVisualPreferences(next);
  return next;
}

function applyRewardShopVisualPreferences(prefs = getRewardShopPreferences()) {
  document.documentElement.classList.toggle("compact-reward-cards", !!prefs.compact_cards);
}

function setActiveRewardSort(value) {
  const safeValue = REWARD_SORT_LABELS[value] ? value : "price-desc";
  const trigger = qs("#sortFilter");
  const label = qs("[data-sort-label]");
  if (trigger) trigger.dataset.value = safeValue;
  if (label) label.textContent = REWARD_SORT_LABELS[safeValue];
  qsa("[data-sort-value]").forEach((option) => {
    const active = option.dataset.sortValue === safeValue;
    option.classList.toggle("active", active);
    option.setAttribute("aria-selected", String(active));
  });
}

function setRewardSortMenuOpen(open) {
  const dropdown = qs("[data-sort-dropdown]");
  const trigger = qs("#sortFilter");
  if (!dropdown || !trigger) return;
  dropdown.classList.toggle("open", !!open);
  trigger.setAttribute("aria-expanded", String(!!open));
}

function getActiveAvailabilityFilter() {
  return qs("[data-afford-filter].active")?.dataset.affordFilter || "all";
}

function setActiveAvailabilityFilter(value) {
  qsa("[data-afford-filter]").forEach((button) => {
    const active = button.dataset.affordFilter === value;
    button.classList.toggle("active", active);
    button.setAttribute("aria-pressed", String(active));
  });
}

function hasActiveRewardFilters() {
  return !!(
    (qs("#skinSearch")?.value || "").trim() ||
    (qs("#minPriceFilter")?.value || "").trim() ||
    (qs("#maxPriceFilter")?.value || "").trim() ||
    getActiveAvailabilityFilter() !== "all"
  );
}

function clearRewardFilterControls() {
  const search = qs("#skinSearch");
  const minPrice = qs("#minPriceFilter");
  const maxPrice = qs("#maxPriceFilter");
  if (search) search.value = "";
  if (minPrice) minPrice.value = "";
  if (maxPrice) maxPrice.value = "";
  setActiveAvailabilityFilter("all");
}

function cleanCoinRangeInput(input) {
  if (!input) return;
  const clean = String(input.value || "").replace(/[^0-9]/g, "");
  if (input.value !== clean) input.value = clean;
}

function renderRewards() {
  const grid = qs("#rewardsGrid");
  if (!grid) return;

  const search = qs("#skinSearch");
  const minPrice = qs("#minPriceFilter");
  const maxPrice = qs("#maxPriceFilter");
  const sort = qs("#sortFilter");
  const resultCount = qs("#rewardResultCount");
  const clearFilters = qs("#clearRewardFilters");
  const prefs = getRewardShopPreferences();
  applyRewardShopVisualPreferences(prefs);

  if (!grid.dataset.rewardPrefsHydrated) {
    setActiveRewardSort(prefs.default_sort);
    grid.dataset.rewardPrefsHydrated = "true";
  }

  function apply(animate = false) {
    if (animate) grid.classList.add("is-refreshing");
    const settleGrid = () => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => grid.classList.remove("is-refreshing"));
      });
    };

    const query = (search?.value || "").toLowerCase().trim();
    const minValue = Number(minPrice?.value || "");
    const maxValue = Number(maxPrice?.value || "");
    const hasMin = (minPrice?.value || "").trim() !== "" && Number.isFinite(minValue);
    const hasMax = (maxPrice?.value || "").trim() !== "" && Number.isFinite(maxValue);
    const sortValue = sort?.dataset.value || prefs.default_sort || "price-desc";
    const affordValue = getActiveAvailabilityFilter();
    const balance = Number(currentProfile?.points_balance || 0);
    const signedIn = !!currentUser?.id;
    const activePrefs = getRewardShopPreferences();

    const filtered = rewardItems.filter((item) => {
      const haystack = [item.name, item.description, item.rarity, item.condition, item.market_name].filter(Boolean).join(" ").toLowerCase();
      const cost = getRewardCost(item);
      const available = !rewardIsOutOfStock(item);
      const matchesSearch = !query || haystack.includes(query);
      const matchesMin = !hasMin || cost >= minValue;
      const matchesMax = !hasMax || cost <= maxValue;
      const matchesVisibility = activePrefs.show_out_of_stock || available;
      const matchesAfford =
        affordValue === "all" ||
        (affordValue === "affordable" && signedIn && available && cost <= balance) ||
        (affordValue === "in-stock" && available);

      return matchesSearch && matchesMin && matchesMax && matchesVisibility && matchesAfford;
    });

    const sorted = sortRewardsForShop(filtered, sortValue);
    if (resultCount) {
      const total = rewardItems.length;
      resultCount.textContent = total === 0
        ? "No rewards loaded yet"
        : sorted.length === total
          ? `Showing ${sorted.length.toLocaleString()} rewards`
          : `Showing ${sorted.length.toLocaleString()} of ${total.toLocaleString()} rewards`;
    }
    clearFilters?.classList.toggle("hidden", !hasActiveRewardFilters());

    if (sorted.length === 0) {
      grid.innerHTML = `
        <div class="empty-state empty-action-state">
          <strong>No rewards found.</strong>
          <span>Try another search, change your coin range, or clear the active filters.</span>
          <div class="empty-actions">
            <button class="button button-ghost" type="button" data-clear-reward-filters>Clear filters</button>
            <a class="button button-primary" href="earn.html">Surveys</a>
          </div>
        </div>`;
      settleGrid();
      qs("[data-clear-reward-filters]")?.addEventListener("click", () => {
        clearRewardFilterControls();
        window.__skinquestRewardApply?.(true);
      });
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
      const action = getRewardActionState(item, currentProfile);

      const isFavorited = favoriteRewardIds.has(Number(item.id));

      return `
        <article class="reward-card steam-item ${rarityClass(item)} ${outOfStock ? "is-out" : ""}">
          ${renderRewardArt(item)}
          <button class="favorite-star ${isFavorited ? "is-favorited" : ""}" type="button" data-favorite-star="${item.id}" aria-pressed="${isFavorited}" aria-label="${isFavorited ? "Remove goal star" : "Set as goal"}">
            <svg class="star-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.6l2.95 6.53 7.15.66-5.4 4.73 1.63 7-6.33-3.8-6.33 3.8 1.63-7-5.4-4.73 7.15-.66L12 2.6z"/></svg>
          </button>
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
            <div class="reward-actions reward-actions-smart">
              <button class="button ${action.action === "redeem" ? "button-primary" : "button-ghost"}" type="button" data-reward-action="${escapeHtml(action.action)}" data-redeem="${item.id}" ${action.disabled ? "disabled" : ""}>
                ${escapeHtml(action.label)}
              </button>
              <small>${escapeHtml(action.note)}</small>
            </div>
          </div>
        </article>
      `;
    }).join("");

    qsa("[data-redeem]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        const action = button.dataset.rewardAction || "redeem";
        if (action === "login") return openAuthModal("signup");
        if (action === "trade") return location.href = "settings.html#tradeForm";
        if (action === "earn") return location.href = "earn.html";
        if (action === "out") return;
        requestRedeem(Number(button.dataset.redeem), button);
      });
    });
    qsa("[data-favorite-star]").forEach((button) => {
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        toggleFavoriteReward(button.dataset.favoriteStar, button);
      });
    });
    updateFavoriteCountUi();
    settleGrid();
  }

  window.__skinquestRewardApply = apply;
  if (!grid.dataset.rewardFiltersBound) {
    grid.dataset.rewardFiltersBound = "true";
    const scheduleApply = () => window.__skinquestRewardApply?.(true);
    const scheduleSearchApply = () => {
      window.clearTimeout(window.__skinquestRewardSearchTimer);
      window.__skinquestRewardSearchTimer = window.setTimeout(scheduleApply, 120);
    };

    search?.addEventListener("input", scheduleSearchApply);
    minPrice?.addEventListener("input", () => { cleanCoinRangeInput(minPrice); scheduleSearchApply(); });
    maxPrice?.addEventListener("input", () => { cleanCoinRangeInput(maxPrice); scheduleSearchApply(); });
    clearFilters?.addEventListener("click", () => {
      clearRewardFilterControls();
      scheduleApply();
    });

    qsa("[data-afford-filter]").forEach((button) => {
      button.addEventListener("click", () => {
        setActiveAvailabilityFilter(button.dataset.affordFilter || "all");
        scheduleApply();
      });
    });

    sort?.addEventListener("click", (event) => {
      event.preventDefault();
      setRewardSortMenuOpen(!qs("[data-sort-dropdown]")?.classList.contains("open"));
    });

    qsa("[data-sort-value]").forEach((option) => {
      option.addEventListener("click", (event) => {
        event.preventDefault();
        const value = option.dataset.sortValue || "price-desc";
        setActiveRewardSort(value);
        saveRewardShopPreferences({ default_sort: value });
        setRewardSortMenuOpen(false);
        scheduleApply();
      });
    });

    document.addEventListener("click", (event) => {
      const dropdown = qs("[data-sort-dropdown]");
      if (dropdown && !dropdown.contains(event.target)) setRewardSortMenuOpen(false);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") setRewardSortMenuOpen(false);
    });
  }
  apply(false);
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
        "Your reward request was not created because your Steam trade URL is missing or was not saved correctly. Add it in Settings, save it, then try redeeming again.",
        { title: "Steam trade link required", confirmText: "Open Settings", cancelText: "Stay on rewards", icon: "↗" }
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


function hydrateRewardShopSettingsControls() {
  const prefs = getRewardShopPreferences();
  const showOut = qs("#rewardShowOutOfStock");
  const compact = qs("#rewardCompactCards");
  if (showOut) showOut.checked = !!prefs.show_out_of_stock;
  if (compact) compact.checked = !!prefs.compact_cards;
  qsa("[data-reward-default-sort]").forEach((button) => {
    button.classList.toggle("active", button.dataset.rewardDefaultSort === prefs.default_sort);
  });
}

function getSelectedRewardDefaultSort() {
  return qs("[data-reward-default-sort].active")?.dataset.rewardDefaultSort || getRewardShopPreferences().default_sort;
}


function getCurrentAuthMode() {
  return qs("[data-auth-tab].active")?.dataset.authTab === "login" ? "login" : "signup";
}

async function startSteamAuthFromModal() {
  const button = qs("#steamLoginButton");
  const previousText = button?.querySelector("strong")?.textContent || "Continue with Steam";
  const mode = getCurrentAuthMode();

  try {
    if (button) {
      button.disabled = true;
      const label = button.querySelector("strong");
      if (label) label.textContent = "Opening Steam...";
    }

    const response = await fetch(STEAM_AUTH_START_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode })
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok || !data.url) {
      throw new Error(data.error || "Could not start Steam sign-in.");
    }

    window.location.href = data.url;
  } catch (error) {
    console.error("Steam auth failed", error);
    showMessage(error.message || "Could not start Steam sign-in.", "error");
    if (button) {
      button.disabled = false;
      const label = button.querySelector("strong");
      if (label) label.textContent = previousText;
    }
  }
}

function getSteamConnectionLabel(profile) {
  const steamName = profile?.steam_name || profile?.steam_persona_name;
  if (steamName) return `Connected as ${steamName}`;
  if (profile?.steam_id) return `Connected: ${profile.steam_id}`;
  return "Not connected";
}

function updateSteamLinkedService(profile) {
  const card = qs("#linkedSteamService");
  const connectButton = qs("#connectSteamButton");
  const disconnectButton = qs("#disconnectSteamButton");
  const status = qs("#steamLoginStatus");
  const description = qs("#steamLoginDescription");
  if (!card || !connectButton || !status) return;

  const connected = !!profile?.steam_id;
  card.classList.toggle("is-connected", connected);
  card.classList.toggle("is-planned", !connected);
  connectButton.classList.toggle("hidden", connected);
  disconnectButton?.classList.toggle("hidden", !connected);
  status.classList.toggle("hidden", !connected);
  status.textContent = connected ? "Connected" : "Not connected";
  if (description) {
    description.textContent = connected
      ? getSteamConnectionLabel(profile)
      : "Connect your Steam account or use Steam sign-in from the login window.";
  }
}

async function connectSteamAccount() {
  const button = qs("#connectSteamButton");
  const previousText = button?.textContent || "Connect";

  try {
    const { data: { session } } = await sb.auth.getSession();
    if (!session?.access_token) {
      openAuthModal("login");
      return;
    }

    if (button) {
      button.disabled = true;
      button.textContent = "Opening Steam...";
    }

    const response = await fetch(STEAM_AUTH_START_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${session.access_token}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ mode: "connect" })
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok || !data.url) {
      throw new Error(data.error || "Could not start Steam connection.");
    }

    window.location.href = data.url;
  } catch (error) {
    console.error("Steam connect failed", error);
    showMessage(error.message || "Could not start Steam connection.", "error");
    if (button) {
      button.disabled = false;
      button.textContent = previousText;
    }
  }
}


async function disconnectSteamAccount() {
  const button = qs("#disconnectSteamButton");
  const previousText = button?.textContent || "Disconnect";
  const confirmed = await showConfirm(
    "Your email login will still work, but Steam sign-in will stop working until you connect Steam again.",
    {
      title: "Disconnect Steam?",
      confirmText: "Disconnect Steam",
      cancelText: "Keep connected",
      icon: "ST",
      danger: true
    }
  );
  if (!confirmed) return;

  try {
    const { data: { session } } = await sb.auth.getSession();
    if (!session?.access_token) {
      openAuthModal("login");
      return;
    }

    if (button) {
      button.disabled = true;
      button.textContent = "Disconnecting...";
    }

    const response = await fetch(STEAM_AUTH_DISCONNECT_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${session.access_token}`,
        "Content-Type": "application/json"
      }
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(data.error || "Could not disconnect Steam.");
    }

    showMessage("Steam account disconnected.", "success");
    await refreshAll();
  } catch (error) {
    console.error("Steam disconnect failed", error);
    showMessage(error.message || "Could not disconnect Steam.", "error");
    if (button) {
      button.disabled = false;
      button.textContent = previousText;
    }
  }
}

function handleSteamConnectResult() {
  if (!document.body.classList.contains("settings-page")) return;
  const params = new URLSearchParams(window.location.search);
  const result = params.get("steam");
  if (!result) return;

  const messages = {
    connected: ["Steam account connected.", "success"],
    missing_state: ["Steam connection could not start correctly. Try again.", "error"],
    invalid_state: ["Steam connection expired or was not recognized. Try again.", "error"],
    expired_state: ["Steam connection expired. Try again.", "error"],
    invalid_login: ["Steam could not verify the login. Try again.", "error"],
    no_steam_id: ["Steam did not return a SteamID. Try again.", "error"],
    save_failed: ["Steam verified, but SkinQuest could not save it. It may already be connected to another account.", "error"],
    disconnected: ["Steam account disconnected.", "success"]
  };
  const [text, type] = messages[result] || ["Steam connection finished.", "success"];
  showMessage(text, type);

  params.delete("steam");
  const cleanQuery = params.toString();
  const cleanUrl = `${window.location.pathname}${cleanQuery ? `?${cleanQuery}` : ""}${window.location.hash}`;
  window.history.replaceState({}, document.title, cleanUrl);
}

async function initSettingsPage() {
  if (!qs("#settingsAuthSection") && !qs("#notificationSettingsForm")) return;

  qsa("[data-future-service]").forEach((button) => {
    button.addEventListener("click", () => {
      showMessage(`${button.dataset.futureService} linking is planned for a later version.`);
    });
  });

  qs("#connectSteamButton")?.addEventListener("click", connectSteamAccount);
  qs("#disconnectSteamButton")?.addEventListener("click", disconnectSteamAccount);
  handleSteamConnectResult();

  qsa("[data-reward-default-sort]").forEach((button) => {
    button.addEventListener("click", () => {
      qsa("[data-reward-default-sort]").forEach((item) => item.classList.remove("active"));
      button.classList.add("active");
    });
  });

  qs("#rewardShopSettingsForm")?.addEventListener("submit", (event) => {
    event.preventDefault();
    const button = event.currentTarget.querySelector('button[type="submit"]');
    const reset = setButtonBusy(button, "Saving...");
    saveRewardShopPreferences({
      default_sort: getSelectedRewardDefaultSort(),
      show_out_of_stock: !!qs("#rewardShowOutOfStock")?.checked,
      compact_cards: !!qs("#rewardCompactCards")?.checked
    });
    hydrateRewardShopSettingsControls();
    reset();
    flashButtonSaved(button, "Saved");
    showMessage("Reward browsing preferences saved.", "success");
  });

  qsa("[data-open-support-shortcut]").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelector("[data-support-toggle]")?.click();
    });
  });

  qs("#notificationSettingsForm")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = event.currentTarget.querySelector('button[type="submit"]');
    const reset = setButtonBusy(button, "Saving...");
    const user = await getSessionUser();
    if (!user) {
      reset();
      return openAuthModal("login");
    }

    const prefs = {
      reward_updates: !!qs("#notifyRewardUpdates")?.checked,
      offer_issues: !!qs("#notifyOfferIssues")?.checked,
      product_updates: !!qs("#notifyProductUpdates")?.checked
    };

    await trySaveNotificationPreferences(user, prefs);
    reset();
    flashButtonSaved(button, "Saved");
    showMessage("Notification preferences saved.", "success");
  });

  await refreshSettingsPage();
}

async function refreshSettingsPage() {
  const authSection = qs("#settingsAuthSection");
  const accountSection = qs("#settingsAccountSection");
  const loadingSection = qs("#settingsLoadingSection");
  if (!authSection || !accountSection) return;

  loadingSection?.classList.remove("hidden");
  authSection.classList.add("hidden");
  accountSection.classList.add("hidden");

  const user = await getSessionUser();
  if (!user) {
    loadingSection?.classList.add("hidden");
    authSection.classList.remove("hidden");
    accountSection.classList.add("hidden");
    return;
  }

  const profile = await ensureProfile(user).catch(() => null);
  const storedPrefs = getStoredNotificationPreferences(user.id);
  const prefs = {
    reward_updates: profile?.notification_reward_updates ?? storedPrefs.reward_updates,
    offer_issues: profile?.notification_offer_issues ?? storedPrefs.offer_issues,
    product_updates: profile?.notification_product_updates ?? storedPrefs.product_updates
  };

  const email = displayAccountEmail(user, profile);
  const shortId = user.id ? `${user.id.slice(0, 8)}...${user.id.slice(-6)}` : "Unknown id";

  const avatar = qs("#settingsAvatar");
  if (avatar) avatar.textContent = userInitial(user);
  const emailEl = qs("#settingsEmail");
  if (emailEl) emailEl.textContent = email;
  const idEl = qs("#settingsUserId");
  if (idEl) idEl.textContent = `User ID: ${shortId}`;

  const tradeReady = !!profile?.steam_trade_url && isValidSteamTradeUrl(profile.steam_trade_url);
  const tradeStatusEl = qs("#settingsTradeStatus");
  if (tradeStatusEl) tradeStatusEl.textContent = tradeReady ? "Saved and valid" : "Missing";
  updateSteamLinkedService(profile);
  const setReadyItem = (itemSelector, textSelector, state, text) => {
    const item = qs(itemSelector);
    const textEl = qs(textSelector);
    if (textEl) textEl.textContent = text;
    if (item) {
      item.classList.toggle("is-ready", state === "ready");
      item.classList.toggle("is-warning", state === "warning");
      item.classList.toggle("is-muted", state === "muted");
    }
  };
  setReadyItem("#readinessEmailItem", "#readinessEmailText", "ready", "Connected and signed in");
  setReadyItem("#readinessTradeItem", "#readinessTradeText", tradeReady ? "ready" : "warning", tradeReady ? "Saved and valid" : "Missing or incomplete");
  setReadyItem("#readinessRedeemItem", "#readinessRedeemText", tradeReady ? "ready" : "warning", tradeReady ? "Ready to redeem rewards" : "Add trade URL before redeeming");

  hydrateRewardShopSettingsControls();

  const tradeUrl = qs("#tradeUrl");
  if (tradeUrl) tradeUrl.value = profile?.steam_trade_url || "";

  const setChecked = (selector, value) => {
    const el = qs(selector);
    if (el) el.checked = !!value;
  };
  setChecked("#notifyRewardUpdates", prefs.reward_updates);
  setChecked("#notifyOfferIssues", prefs.offer_issues);
  setChecked("#notifyProductUpdates", prefs.product_updates);

  loadingSection?.classList.add("hidden");
  authSection.classList.add("hidden");
  accountSection.classList.remove("hidden");
}

function getSupportContext(user) {
  return {
    page_url: location.href,
    user_agent: navigator.userAgent || null,
    account_email: user?.email || null,
    browser_language: navigator.language || null
  };
}

function initSupportWidget() {
  if (document.querySelector("[data-support-widget]")) return;

  const shell = document.createElement("div");
  shell.className = "support-widget";
  shell.dataset.supportWidget = "true";
  shell.innerHTML = `
    <button class="support-fab" type="button" aria-expanded="false" aria-label="Open support" data-support-toggle>
      <span aria-hidden="true">✦</span>
      <small>Help</small>
    </button>
    <section class="support-panel" aria-label="Support panel" aria-hidden="true" data-support-panel>
      <div class="support-panel-head">
        <div>
          <span class="support-kicker">SkinQuest support</span>
          <strong>Need help?</strong>
          <p>Send a support request and we’ll reply by email if needed.</p>
        </div>
        <button type="button" aria-label="Close support" data-support-close>×</button>
      </div>
      <form class="support-form" data-support-form>
        <label>Email
          <input data-support-email type="email" placeholder="you@example.com" autocomplete="email" required />
        </label>
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
          <textarea data-support-message rows="4" maxlength="1800" placeholder="Tell us what happened. Include reward name, offer, or trade details if relevant." required></textarea>
        </label>
        <input class="support-honeypot" data-support-website tabindex="-1" autocomplete="off" aria-hidden="true" placeholder="Website" />
        <button class="button button-primary" type="submit" data-support-submit>Send request</button>
        <p class="fine-print">Requests are saved to the admin support inbox. For urgent issues, email <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.</p>
      </form>
    </section>
  `;

  document.body.appendChild(shell);

  const toggle = shell.querySelector("[data-support-toggle]");
  const panel = shell.querySelector("[data-support-panel]");
  const close = shell.querySelector("[data-support-close]");
  const emailInput = shell.querySelector("[data-support-email]");
  const setOpen = (open) => {
    panel.classList.toggle("open", open);
    panel.setAttribute("aria-hidden", String(!open));
    toggle.classList.toggle("open", open);
    toggle.setAttribute("aria-expanded", String(open));
    if (open) setTimeout(() => emailInput?.focus(), 80);
  };

  toggle.addEventListener("click", async () => {
    const willOpen = !panel.classList.contains("open");
    if (willOpen && emailInput && !emailInput.value) {
      const user = await getSessionUser();
      if (user?.email) emailInput.value = user.email;
    }
    setOpen(willOpen);
  });
  close.addEventListener("click", () => setOpen(false));

  shell.querySelector("[data-support-form]")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const topic = shell.querySelector("[data-support-topic]")?.value || "Support request";
    const email = shell.querySelector("[data-support-email]")?.value.trim().toLowerCase();
    const message = shell.querySelector("[data-support-message]")?.value.trim();
    const honeypot = shell.querySelector("[data-support-website]")?.value.trim();
    const submitButton = shell.querySelector("[data-support-submit]");

    if (honeypot) return;
    if (!email || !isValidEmailAddress(email)) return showMessage("Enter a valid email so support can reply.", "error");
    if (!message || message.length < 8) return showMessage("Write a short message before sending support.", "error");

    submitButton.disabled = true;
    const previousText = submitButton.textContent;
    submitButton.textContent = "Sending...";

    try {
      const user = await getSessionUser();
      const context = getSupportContext(user);
      const { error } = await sb.from("support_requests").insert({
        user_id: user?.id || null,
        topic,
        message,
        page_url: context.page_url,
        user_agent: context.user_agent,
        account_email: email,
        browser_language: context.browser_language
      });

      if (error) throw error;

      showMessage("Support request sent. We’ll reply by email if needed.", "success");
      form.reset();
      setOpen(false);
    } catch (error) {
      console.error("Support request failed", error);
      const subject = encodeURIComponent(`SkinQuest support - ${topic}`);
      const body = encodeURIComponent([
        `Topic: ${topic}`,
        `Email: ${email}`,
        `Page: ${location.href}`,
        "",
        message
      ].join("\n"));
      showMessage("Could not save the support request. Opening email instead.", "error");
      location.href = `mailto:${SUPPORT_EMAIL}?subject=${subject}&body=${body}`;
    } finally {
      submitButton.disabled = false;
      submitButton.textContent = previousText || "Send request";
    }
  });
}

async function initDashboard() {
  const tradeForm = qs("#tradeForm");
  if (tradeForm) {
    tradeForm.addEventListener("submit", async (event) => {
      event.preventDefault();

      const user = await getSessionUser();
      if (!user) return openAuthModal("login");

      const button = event.currentTarget.querySelector('button[type="submit"]');
      const steamTradeUrl = qs("#tradeUrl")?.value.trim();
      if (steamTradeUrl && !isValidSteamTradeUrl(steamTradeUrl)) {
        return showMessage("That does not look like a valid Steam trade URL. It should include steamcommunity.com/tradeoffer/new/?partner=...&token=...");
      }

      const reset = setButtonBusy(button, "Saving...");
      try {
        await saveSteamTradeUrlForUser(user, steamTradeUrl);
      } catch (error) {
        reset();
        return showMessage(error.message, "error");
      }

      reset();
      flashButtonSaved(button, "Saved");
      showMessage("Steam trade URL saved.", "success");
      await refreshAll();
    });
  }

  qs("#logoutButton")?.addEventListener("click", confirmAndSignOut);

  await refreshDashboard();
}

async function refreshDashboard() {
  const authSection = qs("#authSection");
  const accountSection = qs("#accountSection");
  const loadingSection = qs("#dashboardLoadingSection");
  if (!authSection || !accountSection) return;

  loadingSection?.classList.remove("hidden");
  authSection.classList.add("hidden");
  accountSection.classList.add("hidden");

  const user = await getSessionUser();

  if (!user) {
    loadingSection?.classList.add("hidden");
    authSection.classList.remove("hidden");
    accountSection.classList.add("hidden");
    return;
  }

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

  setText("#accountEmail", displayAccountEmail(user, profile) || "Unknown");
  setText("#balanceDisplay", Number(profile.points_balance || 0).toLocaleString());
  setText("#totalEarnedDisplay", Number(totalEarned).toLocaleString());
  setText("#levelDisplay", progress.level);
  setText("#xpDisplay", `${Number(totalEarned - progress.currentFloor).toLocaleString()} / ${COINS_PER_LEVEL.toLocaleString()} earned coins`);
  setText("#levelText", `Level ${progress.level}`);
  setText("#nextLevelText", `${Number(Math.max(0, progress.nextFloor - totalEarned)).toLocaleString()} coins to Level ${progress.level + 1}`);

  const xpBar = qs("#xpBarFill");
  if (xpBar) xpBar.style.width = `${progress.progress}%`;

  updateRedeemBlocker(profile);
  await renderGoalRewards(user, profile);

  const { data: redemptions, error } = await sb
    .from("redemption_requests")
    .select("*")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  if (!error) {
    const userRedemptions = redemptions || [];
    setText("#pendingDisplay", userRedemptions.filter((item) => ["pending", "reviewing", "trade_sent"].includes(item.status)).length);
    updateGetStartedPanel(profile, totalEarned, userRedemptions);
    renderRedeemHistory(userRedemptions);
  } else {
    setText("#pendingDisplay", "—");
    updateGetStartedPanel(profile, totalEarned, []);
  }

  await renderCoinHistory(user.id);

  loadingSection?.classList.add("hidden");
  authSection.classList.add("hidden");
  accountSection.classList.remove("hidden");

  if (shouldShowSteamEmailPrompt(user)) {
    setTimeout(() => showSteamEmailPrompt(user), 260);
  }
}

async function renderGoalRewards(user, profile) {
  const panel = qs("#goalRewardsPanel");
  const list = qs("#goalRewardsList");
  if (!panel || !list || !user?.id) return;

  await loadFavoriteRewards(user.id);

  if (favoriteRewardIds.size === 0) {
    panel.classList.add("hidden");
    list.innerHTML = "";
    return;
  }

  const ids = Array.from(favoriteRewardIds);
  const { data, error } = await sb.from("reward_items").select("*").in("id", ids);

  if (error || !data || data.length === 0) {
    panel.classList.add("hidden");
    list.innerHTML = "";
    return;
  }

  panel.classList.remove("hidden");
  const balance = Number(profile?.points_balance || 0);

  list.innerHTML = data.map((item) => {
    const cost = getRewardCost(item);
    const pct = cost > 0 ? Math.max(0, Math.min(100, (balance / cost) * 100)) : 100;
    const canClaim = balance >= cost && !rewardIsOutOfStock(item);

    return `
      <div class="goal-reward-card">
        ${renderRewardArt(item)}
        <div class="goal-reward-info">
          <div class="goal-reward-head">
            <h3>${escapeHtml(item.name)}</h3>
            <button class="favorite-star is-favorited" type="button" data-favorite-star="${item.id}" aria-pressed="true" aria-label="Remove goal star">
              <svg class="star-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.6l2.95 6.53 7.15.66-5.4 4.73 1.63 7-6.33-3.8-6.33 3.8 1.63-7-5.4-4.73 7.15-.66L12 2.6z"/></svg>
            </button>
          </div>
          <p class="muted goal-reward-coins">${coinIcon("coin-icon-small")} ${balance.toLocaleString()} / ${cost.toLocaleString()} coins</p>
          ${canClaim
            ? `<button class="button button-primary goal-claim-button" type="button" data-claim-reward="${escapeHtml(item.name)}">Claim reward</button>`
            : `<div class="goal-progress-bar" role="progressbar" aria-valuenow="${Math.round(pct)}" aria-valuemin="0" aria-valuemax="100"><span style="width:${pct}%"></span></div>`}
        </div>
      </div>
    `;
  }).join("");

  qsa("#goalRewardsList [data-favorite-star]").forEach((button) => {
    button.addEventListener("click", async (event) => {
      event.preventDefault();
      await toggleFavoriteReward(button.dataset.favoriteStar, button);
      await renderGoalRewards(user, profile);
    });
  });

  qsa("#goalRewardsList [data-claim-reward]").forEach((button) => {
    button.addEventListener("click", () => {
      location.href = `rewards.html?search=${encodeURIComponent(button.dataset.claimReward || "")}`;
    });
  });
}

function updateGetStartedPanel(profile, totalEarned, redemptions = []) {
  const panel = qs("#getStartedPanel");
  if (!panel) return;

  const hasTrade = !!profile?.steam_trade_url && isValidSteamTradeUrl(profile.steam_trade_url);
  const hasEarned = Number(totalEarned || 0) > 0;
  const hasRedeemed = Array.isArray(redemptions) && redemptions.length > 0;

  if (hasTrade && hasEarned && hasRedeemed) {
    panel.classList.add("hidden");
    return;
  }

  panel.classList.remove("hidden");
  panel.innerHTML = `
    <div class="section-headline">
      <div>
        <span class="pill">Get started</span>
        <h2>Set up your reward flow</h2>
        <p class="muted">Complete these basics so your first redeem request is smooth.</p>
      </div>
      <a class="button button-primary" href="${hasTrade ? "earn.html" : "settings.html#tradeForm"}">${hasTrade ? "Open surveys" : "Add trade URL"}</a>
    </div>
    <div class="getting-started-steps">
      <a class="setup-step ${hasTrade ? "complete" : "active"}" href="settings.html#tradeForm">
        <strong>${hasTrade ? "✓" : "1"}</strong>
        <span>Save Steam trade URL</span>
        <small>${hasTrade ? "Ready for rewards" : "Required before redeeming"}</small>
      </a>
      <a class="setup-step ${hasEarned ? "complete" : hasTrade ? "active" : ""}" href="earn.html">
        <strong>${hasEarned ? "✓" : "2"}</strong>
        <span>Complete surveys</span>
        <small>${hasEarned ? "Coins confirmed" : "Open verified survey tasks"}</small>
      </a>
      <a class="setup-step ${hasRedeemed ? "complete" : hasEarned ? "active" : ""}" href="rewards.html">
        <strong>${hasRedeemed ? "✓" : "3"}</strong>
        <span>Redeem a reward</span>
        <small>${hasRedeemed ? "Request created" : "Pick a fixed reward"}</small>
      </a>
    </div>
  `;
}

function renderRedeemHistory(redemptions) {
  const redeemHistory = qs("#redeemHistory");
  if (!redeemHistory) return;

  if (!redemptions || redemptions.length === 0) {
    redeemHistory.className = "empty-state empty-action-state";
    redeemHistory.innerHTML = `
      <strong>No redeem requests yet.</strong>
      <span>Once you redeem a reward, your request status appears here.</span>
      <a class="button button-primary" href="rewards.html">Browse rewards</a>
    `;
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
    coinHistory.className = "empty-state empty-action-state";
    coinHistory.innerHTML = `
      <strong>No coin history yet.</strong>
      <span>Complete your first partner task to start earning coins.</span>
      <a class="button button-primary" href="earn.html">Surveys</a>
    `;
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

  const isSteamAuth = new URLSearchParams(location.search).get("steam") === "login";
  setState("loading", isSteamAuth ? "Signing in with Steam..." : "Confirming your email...", isSteamAuth ? "Finishing your Steam sign-in. This usually takes a second." : "Finishing your SkinQuest sign-in. This usually takes a second.");

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
      setState("warning", isSteamAuth ? "Steam link opened" : "Email link opened", isSteamAuth ? "Steam sign-in opened, but no active session was found. Try signing in again." : "Your email link was opened, but no active session was found. Try signing in now. If Supabase still sends you here, check the redirect URL settings.");
      if (actions) actions.innerHTML = `<button class="button button-primary" data-open-auth="login">Sign in</button><a class="button button-ghost" href="index.html">Home</a>`;
      return;
    }

    await ensureProfile(user);
    setState("success", isSteamAuth ? "Steam sign-in complete" : "Email confirmed", isSteamAuth ? "You are now signed in with Steam." : "Your SkinQuest account is ready. You can now earn coins and redeem rewards.");
    if (actions) actions.innerHTML = `<a class="button button-primary" href="dashboard.html">Go to dashboard</a><a class="button button-ghost" href="rewards.html">View rewards</a>`;
    await updateNavAuthState();
  } catch (error) {
    setState("error", isSteamAuth ? "Could not sign in with Steam" : "Could not confirm email", error.message || "The confirmation link could not be processed.");
    if (actions) actions.innerHTML = `<button class="button button-primary" data-open-auth="login">Try signing in</button><a class="button button-ghost" href="index.html">Home</a>`;
  }
}

function initOwnerRoleForm() {
  const form = qs("#ownerRoleForm");
  if (!form || form.dataset.bound === "true") return;
  form.dataset.bound = "true";

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const identifier = qs("#roleUserIdentifier")?.value.trim();
    const role = qs("#roleValue")?.value || "admin";
    if (!identifier) return showMessage("Enter the user's email or user id.", "error");

    const confirmed = await showConfirm(
      role === "remove" ? `Remove admin access from ${identifier}?` : `Set ${identifier} as ${role}?`,
      {
        title: "Update admin role",
        confirmText: role === "remove" ? "Remove access" : "Save role",
        cancelText: "Cancel",
        danger: role === "remove",
        icon: role === "owner" ? "★" : "AD"
      }
    );
    if (!confirmed) return;

    const { error } = await sb.rpc("owner_set_admin_role", {
      p_user_identifier: identifier,
      p_role: role
    });

    if (error) return showMessage(`Could not update role: ${error.message}`, "error");
    showMessage("Admin role updated.", "success");
    form.reset();
    await loadAdminUsers();
  });
}

async function loadAdminUsers() {
  const list = qs("#adminUsersList");
  if (!list) return;

  const { data, error } = await sb
    .from("admin_users")
    .select("user_id, role, created_at")
    .order("role", { ascending: false })
    .order("created_at", { ascending: true });

  if (error) {
    list.className = "empty-state compact-empty";
    list.textContent = `Could not load admin users: ${error.message}`;
    return;
  }

  if (!data || data.length === 0) {
    list.className = "empty-state compact-empty";
    list.textContent = "No admin users added yet.";
    return;
  }

  list.className = "admin-users-list";
  list.innerHTML = data.map((item) => `
    <div class="admin-user-row">
      <div>
        <strong>${escapeHtml(item.role || "admin")}</strong>
        <p class="muted">${escapeHtml(item.user_id)} · added ${formatDate(item.created_at)}</p>
      </div>
      <span class="role-badge">${escapeHtml(item.role || "admin")}</span>
    </div>
  `).join("");
}

async function loadAdminSupportRequests() {
  const list = qs("#adminSupportRequests");
  if (!list) return;

  const { data, error } = await sb
    .from("support_requests")
    .select("*")
    .or("status.is.null,status.eq.new,status.eq.open")
    .order("created_at", { ascending: false })
    .limit(20);

  if (error) {
    list.className = "empty-state";
    list.textContent = `Could not load support requests: ${error.message}`;
    return;
  }

  if (!data || data.length === 0) {
    list.className = "empty-state";
    list.textContent = "No open support requests. Resolved requests are hidden from this list.";
    return;
  }

  list.className = "admin-support-list";
  list.innerHTML = data.map((item) => `
    <article class="admin-support-row status-${escapeHtml(item.status || "new")}">
      <div>
        <div class="admin-row-meta">
          <span class="status-pill">${escapeHtml(item.status || "new")}</span>
          <span>${formatDate(item.created_at)}</span>
        </div>
        <strong>${escapeHtml(item.topic || "Support request")}</strong>
        <p>${escapeHtml(item.message || "")}</p>
        <div class="support-context-grid">
          <span><b>User</b>${escapeHtml(item.user_id || "Unknown")}</span>
          <span><b>Email</b>${escapeHtml(item.account_email || "Not captured")}</span>
          <span><b>Page</b>${escapeHtml(item.page_url || "Unknown")}</span>
          <span><b>Browser</b>${escapeHtml((item.user_agent || "Unknown").slice(0, 120))}</span>
        </div>
        ${item.page_url ? `<a class="mini-link" href="${escapeHtml(item.page_url)}" target="_blank" rel="noopener">Open reported page</a>` : ""}
      </div>
      <div class="admin-actions vertical">
        <button class="button button-ghost" type="button" data-copy="${escapeHtml(item.user_id || "")}" data-copy-label="user id">Copy user ID</button>
        <button class="button button-ghost" type="button" data-copy="${escapeHtml(item.account_email || "")}" data-copy-label="email">Copy email</button>
        <button class="button button-ghost" type="button" data-support-status="open" data-support-id="${item.id}">Open</button>
        <button class="button button-ghost" type="button" data-support-status="resolved" data-support-id="${item.id}">Resolved</button>
      </div>
    </article>
  `).join("");

  bindCopyButtons(list);

  qsa("[data-support-status]").forEach((button) => {
    button.addEventListener("click", async () => {
      const { error: updateError } = await sb
        .from("support_requests")
        .update({ status: button.dataset.supportStatus })
        .eq("id", button.dataset.supportId);
      if (updateError) return showMessage(updateError.message, "error");
      await loadAdminSupportRequests();
      await loadAdminSystemStatus();
    });
  });
}

function bindCopyButtons(scope = document) {
  scope.querySelectorAll("[data-copy]").forEach((button) => {
    if (button.dataset.copyBound === "true") return;
    button.dataset.copyBound = "true";
    button.addEventListener("click", () => copyToClipboard(button.dataset.copy || "", `Copied ${button.dataset.copyLabel || "value"}.`));
  });
}

function openSafeUrl(url) {
  const value = String(url || "").trim();
  if (!value) return showMessage("No link to open yet.", "error");
  try {
    const parsed = new URL(value);
    if (!["http:", "https:"].includes(parsed.protocol)) throw new Error("Unsupported URL");
    window.open(parsed.href, "_blank", "noopener");
  } catch {
    showMessage("That link does not look like a valid URL.", "error");
  }
}

async function loadAdminSystemStatus() {
  const grid = qs("#adminSystemStatus");
  if (!grid) return;

  let openRequests = "—";
  let openSupport = "—";
  let activeRewards = "—";

  try {
    const { count } = await sb.from("redemption_requests").select("id", { count: "exact", head: true }).in("status", ["pending", "reviewing", "trade_sent"]);
    openRequests = Number(count || 0).toLocaleString();
  } catch {}

  try {
    const { count } = await sb.from("support_requests").select("id", { count: "exact", head: true }).in("status", ["new", "open"]);
    openSupport = Number(count || 0).toLocaleString();
  } catch {}

  try {
    const { count } = await sb.from("reward_items").select("id", { count: "exact", head: true }).eq("active", true);
    activeRewards = Number(count || 0).toLocaleString();
  } catch {}

  grid.innerHTML = `
    <div class="system-status-card online"><span>Offerwall</span><strong>Online</strong><small>CPX link active</small></div>
    <div class="system-status-card manual"><span>Rewards</span><strong>Manual review</strong><small>${activeRewards} active rewards</small></div>
    <div class="system-status-card attention"><span>Open requests</span><strong>${openRequests}</strong><small>Pending / reviewing / sent</small></div>
    <div class="system-status-card support"><span>Support</span><strong>${openSupport}</strong><small>New or open messages</small></div>
  `;
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

  const owner = isOwner(user);
  qs("#adminRoleBadge") && (qs("#adminRoleBadge").textContent = owner ? "Owner" : "Admin");
  qsa("[data-owner-only]").forEach((section) => section.classList.toggle("hidden", !owner));
  qs("#ownerToolsLocked")?.classList.toggle("hidden", owner);

  qs("#refreshAdmin")?.addEventListener("click", async () => {
    await loadAdminRequests();
    await loadAdminSupportRequests();
    await loadAdminSystemStatus();
    if (owner) {
      await loadAdminUsers();
      await loadAdminRewards();
    }
  });

  qs("#adminStatusFilter")?.addEventListener("change", loadAdminRequests);
  if (owner) {
    initOwnerRoleForm();
    initAdminRewardForm();
    initAdminCoinForm();
  }

  await loadAdminRequests();
  await loadAdminSupportRequests();
  await loadAdminSystemStatus();
  if (owner) {
    await loadAdminUsers();
    await loadAdminRewards();
  }
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
          <div class="admin-inline-tools">
            <button class="mini-button" type="button" data-copy="${escapeHtml(item.steam_trade_url || "")}" data-copy-label="trade URL">Copy trade URL</button>
            <button class="mini-button" type="button" data-open-url="${escapeHtml(item.steam_trade_url || "")}">Open trade URL</button>
            <button class="mini-button" type="button" data-copy="${escapeHtml(item.user_id || "")}" data-copy-label="user ID">Copy user ID</button>
          </div>
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
        <button class="button button-ghost" type="button" data-copy="Your SkinQuest reward request for ${escapeHtml(item.reward_name)} has been updated to ${escapeHtml(formatStatus(item.status))}. Please check your SkinQuest dashboard for details." data-copy-label="user update message">Copy user message</button>
        <button class="button button-ghost" type="button" data-admin-quick="completed" data-request-id="${item.id}">Completed</button>
        <button class="button button-danger" type="button" data-admin-quick="rejected" data-request-id="${item.id}">Reject + refund</button>
      </div>
    </article>
  `).join("");

  bindCopyButtons(list);
  list.querySelectorAll("[data-open-url]").forEach((button) => {
    button.addEventListener("click", () => openSafeUrl(button.dataset.openUrl || ""));
  });

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
  await loadAdminSystemStatus();
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
  if (qs("#rewardsGrid")) {
    await loadFavoriteRewards(currentUser?.id);
    renderRewards();
    await updateRewardAccountNotice();
  }
  await initAdmin();
}

function applyRewardSearchFromQuery() {
  const params = new URLSearchParams(location.search);
  const search = params.get("search");
  if (!search) return;
  const input = qs("#skinSearch");
  if (!input) return;
  input.value = search;
  window.__skinquestRewardApply?.(true);
}

async function boot() {
  initThemeControls();
  applyRewardShopVisualPreferences();
  initNav();
  initAuthModal();
  initSupportWidget();
  await updateNavAuthState();
  await updateHomeAuthState();
  await initAuthConfirmPage();
  await initOfferwall();

  if (qs("#rewardsGrid")) {
    try {
      await loadRewards();
      await loadFavoriteRewards(currentUser?.id);
      renderRewards();
      applyRewardSearchFromQuery();
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
