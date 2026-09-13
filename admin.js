/* SkinQuest v14.5.6 admin operations workspace */
(() => {
  "use strict";

  const PAGE_SIZE = 75;
  const VIEW_TITLES = {
    overview: "Overview",
    search: "Search results",
    orders: "Reward orders",
    support: "Support inbox",
    users: "Users",
    user: "User account",
    rewards: "Rewards & stock",
    status: "System status",
    promos: "Promo codes",
    audit: "Audit trail",
    coins: "Coin adjustments",
    team: "Team access"
  };
  const OWNER_VIEWS = new Set(["coins", "team"]);
  const ORDER_STATUSES = ["pending", "reviewing", "ordered", "trade_locked", "ready_to_trade", "trade_sent", "completed", "rejected", "refunded", "cancelled"];
  const SUPPORT_STATUSES = ["new", "open", "resolved"];

  const state = {
    bound: false,
    loading: false,
    user: null,
    owner: false,
    view: "overview",
    previousView: "overview",
    kpis: null,
    orders: [],
    support: [],
    users: [],
    userTotal: 0,
    userLoading: false,
    userRequestId: 0,
    userProfileId: null,
    userProfileRequestId: 0,
    userHistorySection: "orders",
    userHistoryItems: [],
    userHistoryTotal: 0,
    userHistoryRequestId: 0,
    userHistoryLoading: false,
    rewards: [],
    rewardOffset: 0,
    rewardTotal: 0,
    rewardLoading: false,
    rewardStats: null,
    pricing: null,
    catalogSync: null,
    editingReward: null,
    statuses: [],
    promos: [],
    promoTotal: 0,
    promoLoading: false,
    promoRequestId: 0,
    audit: [],
    admins: [],
    coinHistory: [],
    profileMap: new Map(),
    globalOrders: [],
    globalSupport: [],
    globalUsers: [],
    orderOffset: 0,
    supportOffset: 0,
    activeDrawer: null,
    lastFocus: null
  };

  const $ = (selector, scope = document) => scope.querySelector(selector);
  const $$ = (selector, scope = document) => Array.from(scope.querySelectorAll(selector));

  function safe(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function textValue(value) {
    return String(value ?? "").trim();
  }

  function formatNumber(value) {
    return Number(value || 0).toLocaleString();
  }

  function formatDateTime(value) {
    if (!value) return "Not recorded";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "Not recorded";
    return date.toLocaleString([], { dateStyle: "medium", timeStyle: "short" });
  }

  function formatShortDate(value) {
    if (!value) return "—";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "—";
    const options = { day: "2-digit", month: "short" };
    if (date.getFullYear() !== new Date().getFullYear()) options.year = "numeric";
    return date.toLocaleDateString([], options);
  }

  function toLocalDateTimeInput(value) {
    if (!value) return "";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    const pad = (n) => String(n).padStart(2, "0");
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  function tradeLockRemaining(value) {
    const end = new Date(value).getTime();
    if (!Number.isFinite(end)) return "Not set";
    let seconds = Math.max(0, Math.ceil((end - Date.now()) / 1000));
    if (seconds <= 0) return "Ready now";
    const days = Math.floor(seconds / 86400); seconds %= 86400;
    const hours = Math.floor(seconds / 3600); seconds %= 3600;
    const minutes = Math.floor(seconds / 60);
    return days > 0 ? `${days}d ${hours}h` : hours > 0 ? `${hours}h ${minutes}m` : `${Math.max(1, minutes)}m`;
  }

  function relativeTime(value) {
    const timestamp = new Date(value || 0).getTime();
    if (!timestamp) return "Unknown time";
    const seconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000));
    if (seconds < 60) return "Just now";
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
    return formatShortDate(value);
  }

  function shortId(value) {
    const id = textValue(value);
    if (!id) return "Unknown";
    if (id.length <= 18) return id;
    return `${id.slice(0, 8)}…${id.slice(-6)}`;
  }

  function orderNumber(item) {
    return textValue(item?.order_number) || `SQ-R-${String(item?.id || 0).padStart(6, "0")}`;
  }

  function orderRewardLabel(item) {
    const name = textValue(item?.reward_name) || "Unknown reward";
    return item?.reward_id == null ? `Deleted item · ${name}` : name;
  }

  function ticketNumber(item) {
    return textValue(item?.ticket_number) || `SQ-S-${String(item?.id || 0).padStart(6, "0")}`;
  }

  function statusLabel(status) {
    const labels = {
      pending: "Pending",
      reviewing: "Reviewing",
      ordered: "Ordered",
      trade_locked: "Trade locked",
      ready_to_trade: "Ready to trade",
      trade_sent: "Trade sent",
      completed: "Completed",
      rejected: "Rejected",
      refunded: "Refunded",
      cancelled: "Cancelled",
      new: "New",
      open: "Open",
      resolved: "Resolved",
      operational: "Operational",
      degraded: "Degraded",
      maintenance: "Maintenance",
      incident: "Incident",
      active: "Active",
      inactive: "Inactive"
    };
    return labels[status] || textValue(status).replaceAll("_", " ") || "Unknown";
  }

  function statusPill(status) {
    const key = textValue(status).toLowerCase() || "unknown";
    return `<span class="admin-status-pill status-${safe(key)}">${safe(statusLabel(key))}</span>`;
  }

  function allowedOrderStatuses(item) {
    const current = textValue(item?.status).toLowerCase() || "pending";
    const mode = item?.fulfillment_mode === "orderable" ? "orderable" : "stocked";
    if (["completed", "rejected", "refunded", "cancelled"].includes(current)) return [current];
    if (current === "trade_sent") return [current, "ready_to_trade", "completed"];

    const terminal = ["rejected", "refunded", "cancelled"];
    const next = mode === "orderable"
      ? {
          pending: ["reviewing", "ordered"],
          reviewing: ["pending", "ordered"],
          ordered: ["trade_locked"],
          trade_locked: ["ready_to_trade"],
          ready_to_trade: ["trade_sent"]
        }
      : {
          pending: ["reviewing", "ready_to_trade"],
          reviewing: ["pending", "ready_to_trade"],
          ordered: ["ready_to_trade"],
          trade_locked: ["ready_to_trade"],
          ready_to_trade: ["trade_sent"]
        };
    return [...new Set([current, ...(next[current] || []), ...terminal])];
  }

  function notify(message, type = "info") {
    if (typeof window.showMessage === "function") window.showMessage(message, type);
    else console[type === "error" ? "error" : "log"](message);
  }

  function confirmAction(message, options = {}) {
    if (typeof window.showConfirm === "function") return window.showConfirm(message, options);
    return Promise.resolve(window.confirm(message));
  }

  function buttonBusy(button, label = "Saving…") {
    if (!button) return () => {};
    const original = button.textContent;
    button.disabled = true;
    button.dataset.busy = "true";
    button.textContent = label;
    return () => {
      button.disabled = false;
      delete button.dataset.busy;
      button.textContent = original;
    };
  }

  function debounce(fn, wait = 320) {
    let timer = null;
    return (...args) => {
      window.clearTimeout(timer);
      timer = window.setTimeout(() => fn(...args), wait);
    };
  }

  async function rpc(name, args = {}) {
    const { data, error } = await sb.rpc(name, args);
    if (error) throw error;
    return data;
  }

  function isMissingRpc(error) {
    const text = String(error?.message || error || "").toLowerCase();
    return text.includes("could not find the function") || text.includes("schema cache") || String(error?.code || "") === "PGRST202";
  }

  function profileLabel(userId, options = {}) {
    const id = textValue(userId);
    if (!id) return options.fallback || "Guest";
    const profile = state.profileMap.get(id);
    if (id === state.user?.id) {
      const currentEmail = textValue(state.user?.email);
      if (currentEmail && !currentEmail.endsWith("@steam.skinquestcs.com")) return currentEmail;
    }
    const verifiedEmail = profile?.contact_email_verified_at ? textValue(profile.contact_email) : "";
    return verifiedEmail || textValue(profile?.email) || textValue(profile?.steam_name) || textValue(profile?.username) || shortId(id);
  }

  function adminLabel(userId) {
    return profileLabel(userId, { fallback: "System" });
  }

  async function hydrateProfiles(ids = []) {
    const unresolved = [...new Set(ids.map(textValue).filter(Boolean))].filter((id) => !state.profileMap.has(id));
    if (!unresolved.length) return;

    for (let index = 0; index < unresolved.length; index += 50) {
      const chunk = unresolved.slice(index, index + 50);
      const { data, error } = await sb
        .from("profiles")
        .select("id,username,steam_name,contact_email,contact_email_verified_at")
        .in("id", chunk);
      if (error) throw error;
      (data || []).forEach((profile) => state.profileMap.set(profile.id, profile));
      chunk.forEach((id) => {
        if (!state.profileMap.has(id)) state.profileMap.set(id, { id });
      });
    }
  }

  function setGate({ title, copy, actions }) {
    const gate = $("#adminLocked");
    const panel = $("#adminPanel");
    if (gate) gate.classList.remove("hidden");
    if (panel) panel.classList.add("hidden");
    if ($("#adminGateTitle")) $("#adminGateTitle").textContent = title;
    if ($("#adminGateCopy")) $("#adminGateCopy").textContent = copy;
    if ($("#adminGateActions")) $("#adminGateActions").innerHTML = actions;
  }

  function showWorkspace() {
    $("#adminLocked")?.classList.add("hidden");
    $("#adminPanel")?.classList.remove("hidden");
  }

  function setSyncState(mode, text) {
    const shell = $(".admin-sync-state");
    shell?.classList.toggle("is-loading", mode === "loading");
    shell?.classList.toggle("has-error", mode === "error");
    if ($("#adminSyncLabel")) $("#adminSyncLabel").textContent = text;
  }

  function updateLastSynced() {
    const now = new Date();
    if ($("#adminLastUpdated")) $("#adminLastUpdated").textContent = `Updated ${now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`;
    if ($("#adminOverviewDate")) $("#adminOverviewDate").textContent = now.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" });
    setSyncState("ready", "Data current");
  }

  function updateNavCounts() {
    const openOrders = Number(state.kpis?.open_rewards ?? state.orders.filter((item) => ["pending", "reviewing", "ordered", "trade_locked", "ready_to_trade", "trade_sent"].includes(item.status)).length);
    const openSupport = Number(state.kpis?.open_support ?? state.support.filter((item) => ["new", "open", null].includes(item.status)).length);
    [["orders", openOrders], ["support", openSupport]].forEach(([key, value]) => {
      const badge = $(`[data-nav-count="${key}"]`);
      if (!badge) return;
      badge.textContent = value > 99 ? "99+" : String(value);
      badge.classList.toggle("hidden", value <= 0);
    });
  }

  function closeSidebar() {
    $("#adminPanel")?.classList.remove("sidebar-open");
    $("#adminMenuButton")?.setAttribute("aria-expanded", "false");
  }

  function showView(view, updateHash = true) {
    const requested = VIEW_TITLES[view] ? view : "overview";
    const next = OWNER_VIEWS.has(requested) && !state.owner ? "overview" : requested;
    if (next !== "search") state.previousView = next;
    state.view = next;

    $$('[data-admin-view-panel]').forEach((panel) => panel.classList.toggle("hidden", panel.dataset.adminViewPanel !== next));
    $$(".admin-nav-item[data-admin-view]").forEach((button) => {
      const active = button.dataset.adminView === next || (next === "user" && button.dataset.adminView === "users");
      button.classList.toggle("active", active);
      if (active) button.setAttribute("aria-current", "page");
      else button.removeAttribute("aria-current");
    });
    if ($("#adminViewTitle")) $("#adminViewTitle").textContent = VIEW_TITLES[next];
    if (updateHash) history.replaceState(null, "", `#${next}`);
    closeSidebar();
    window.scrollTo({ top: 0, behavior: "auto" });
  }

  function openSidebar() {
    $("#adminPanel")?.classList.add("sidebar-open");
    $("#adminMenuButton")?.setAttribute("aria-expanded", "true");
  }

  function bindShell() {
    if (state.bound) return;
    state.bound = true;

    document.addEventListener("click", (event) => {
      const viewButton = event.target.closest("[data-admin-view]");
      if (viewButton) {
        event.preventDefault();
        showView(viewButton.dataset.adminView);
      }

      const viewLink = event.target.closest("[data-admin-view-link]");
      if (viewLink) {
        event.preventDefault();
        showView(viewLink.dataset.adminViewLink);
      }

      if (event.target.closest('[data-admin-action="add-reward"]')) {
        event.preventDefault();
        if (!state.owner) return notify("Owner access is required to add rewards.", "error");
        showView("rewards");
        openRewardEditor(null);
      }
    });

    $("#adminMenuButton")?.addEventListener("click", openSidebar);
    $$('[data-admin-close-sidebar]').forEach((item) => item.addEventListener("click", closeSidebar));
    $("#adminSignOutButton")?.addEventListener("click", () => {
      if (typeof window.confirmAndSignOut === "function") window.confirmAndSignOut();
      else sb.auth.signOut().then(() => { location.href = "/"; });
    });

    $("#refreshAdmin")?.addEventListener("click", (event) => loadAll({ trigger: event.currentTarget }));
    $("#adminStatusFilter")?.addEventListener("change", () => loadOrders({ reset: true }));
    $("#adminSupportStatusFilter")?.addEventListener("change", () => loadSupport({ reset: true }));
    $("#redeemSearch")?.addEventListener("input", debounce(() => loadOrders({ reset: true })));
    $("#supportSearch")?.addEventListener("input", debounce(() => loadSupport({ reset: true })));
    $("#adminUserSearch")?.addEventListener("input", debounce(() => loadUsers({ reset: true })));
    ["adminUserRole", "adminUserLogin", "adminUserSort"].forEach((id) => $("#" + id)?.addEventListener("change", () => loadUsers({ reset: true })));
    $("#rewardAdminSearch")?.addEventListener("input", debounce(() => loadRewards({ reset: true })));
    $("#rewardAdminModeFilter")?.addEventListener("change", () => loadRewards({ reset: true }));
    $("#rewardAdminSort")?.addEventListener("change", () => loadRewards({ reset: true }));
    $("#adminPromoSearch")?.addEventListener("input", debounce(() => loadPromos()));
    $("#adminPromoState")?.addEventListener("change", () => loadPromos());
    $("#adminAuditSearch")?.addEventListener("input", renderAudit);
    $("#ordersLoadMore")?.addEventListener("click", () => loadOrders({ append: true }));
    $("#supportLoadMore")?.addEventListener("click", () => loadSupport({ append: true }));
    $("#usersLoadMore")?.addEventListener("click", () => loadUsers({ append: true }));
    $$("[data-user-history-section]").forEach((button) => button.addEventListener("click", () => loadUserHistory(button.dataset.userHistorySection)));
    $("#userHistoryMore")?.addEventListener("click", () => loadUserHistory(state.userHistorySection, true));
    $("#refreshUserProfile")?.addEventListener("click", () => openUserProfile(state.userProfileId));
    $("#rewardsLoadMore")?.addEventListener("click", () => loadRewards({ append: true }));
    $("#openRewardCreate")?.addEventListener("click", () => openRewardEditor(null));
    $("#rewardFulfillmentMode")?.addEventListener("change", updateRewardEditorMode);
    $("#rewardPricingMode")?.addEventListener("change", updateRewardEditorPricing);
    $("#rewardPricingForm")?.addEventListener("submit", saveRewardPricing);
    $("#syncSteamCatalog")?.addEventListener("click", syncSteamCatalog);

    $("#adminGlobalSearchForm")?.addEventListener("submit", (event) => {
      event.preventDefault();
      executeGlobalSearch($("#adminGlobalSearch")?.value || "");
    });

    document.addEventListener("keydown", (event) => {
      const target = event.target;
      const typing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target instanceof HTMLSelectElement || target?.isContentEditable;
      if (event.key === "/" && !typing && !event.metaKey && !event.ctrlKey && !event.altKey) {
        event.preventDefault();
        $("#adminGlobalSearch")?.focus();
      }
      if (event.key === "Escape") {
        if (!$("#rewardEditorBackdrop")?.classList.contains("hidden")) closeRewardEditor();
        else if (!$("#adminDrawerBackdrop")?.classList.contains("hidden")) closeDrawer();
        else closeSidebar();
      }
    });

    $("#adminDrawerBackdrop")?.addEventListener("pointerdown", (event) => {
      if (event.target === event.currentTarget) closeDrawer();
    });
    $$('[data-close-admin-drawer]').forEach((button) => button.addEventListener("click", closeDrawer));
    $("#rewardEditorBackdrop")?.addEventListener("pointerdown", (event) => {
      if (event.target === event.currentTarget) closeRewardEditor();
    });
    $$('[data-close-reward-editor]').forEach((button) => button.addEventListener("click", closeRewardEditor));

    $("#adminRewardForm")?.addEventListener("submit", saveReward);
    $("#adminPromoForm")?.addEventListener("submit", createPromo);
    $("#ownerRoleForm")?.addEventListener("submit", saveAdminRole);
    $("#adminCoinForm")?.addEventListener("submit", applyCoinAdjustment);
  }

  async function initAdminV145() {
    bindShell();
    setGate({
      title: "Verifying admin access",
      copy: "Checking your signed-in account against the SkinQuest admin directory.",
      actions: '<span class="admin-gate-loader" aria-label="Loading"></span>'
    });

    const user = await getSessionUser();
    state.user = user;
    currentUser = user;
    currentIsAdmin = await fetchAdminStatus(user);
    updateAdminVisibility(user);

    if (!user) {
      setGate({
        title: "Sign in required",
        copy: "Use an approved SkinQuest admin account to open the operations workspace.",
        actions: '<button class="admin-primary-button" type="button" data-open-auth="login">Sign in</button>'
      });
      return;
    }

    if (!isAdmin(user)) {
      setGate({
        title: "Access denied",
        copy: "This account is signed in but is not listed as a SkinQuest admin. Page visibility never grants database access.",
        actions: '<a class="admin-secondary-button" href="/dashboard">Open dashboard</a><button class="admin-danger-button" type="button" data-admin-gate-signout>Sign out</button>'
      });
      $("[data-admin-gate-signout]")?.addEventListener("click", () => confirmAndSignOut());
      return;
    }

    state.owner = isOwner(user);
    $$('[data-owner-only]').forEach((element) => element.classList.toggle("hidden", !state.owner));
    $$('[data-owner-only-view]').forEach((element) => element.classList.toggle("owner-view-disabled", !state.owner));

    const email = typeof window.displayAccountEmail === "function" ? displayAccountEmail(user, currentProfile) : (user.email || "Admin");
    if ($("#adminAccountName")) $("#adminAccountName").textContent = email.split("@")[0] || "Admin";
    if ($("#adminAccountRole")) $("#adminAccountRole").textContent = state.owner ? "Owner" : "Admin";
    if ($("#adminAccountAvatar")) $("#adminAccountAvatar").textContent = (email[0] || "A").toUpperCase();

    showWorkspace();
    const initialView = location.hash.slice(1);
    showView(VIEW_TITLES[initialView] ? initialView : "overview", false);
    await loadAll();

    const params = new URLSearchParams(location.search);
    const linkedOrder = Number(params.get("order"));
    const linkedTicket = Number(params.get("ticket"));
    if (Number.isInteger(linkedOrder) && linkedOrder > 0) {
      showView("orders", false);
      await openOrder(linkedOrder);
    } else if (Number.isInteger(linkedTicket) && linkedTicket > 0) {
      showView("support", false);
      await openSupport(linkedTicket);
    }
  }

  function notifyOrderStatus(requestId) {
    sb.functions.invoke("reward-order-status-notify", { body: { request_id: requestId } })
      .then(({ error }) => { if (error) console.warn("Order status email delayed", error); })
      .catch((error) => console.warn("Order status email delayed", error));
  }

  function retryPendingOrderNotifications(rows) {
    (rows || []).forEach((item) => {
      // Retry failed initial email only while a newly placed order is recent.
      // Legacy orders must not receive a fresh "order received" email months later.
      const placedAt = Date.parse(item?.created_at || "");
      const recentOrder = Number.isFinite(placedAt) && placedAt <= Date.now()
        && Date.now() - placedAt < 24 * 60 * 60 * 1000;
      if (recentOrder && (!item?.admin_notified_at || !item?.user_notified_at)) {
        sb.functions.invoke("reward-order-notify", { body: { request_id: item.id } })
          .then(({ error }) => { if (error) console.warn("Initial order notification retry delayed", error); })
          .catch((error) => console.warn("Initial order notification retry delayed", error));
      }
      const status = textValue(item?.status);
      const statusChangedAt = Date.parse(item?.updated_at || item?.last_handled_at || "");
      const recentStatusChange = Number.isFinite(statusChangedAt) && statusChangedAt <= Date.now()
        && Date.now() - statusChangedAt < 24 * 60 * 60 * 1000;
      const retryable = ["trade_locked", "trade_sent", "completed", "rejected", "refunded", "cancelled"].includes(status)
        || (status === "ready_to_trade" && item?.fulfillment_mode === "orderable");
      const needsUserStatus = item?.last_user_notified_status !== status;
      const needsReadyAdmin = status === "ready_to_trade" && item?.fulfillment_mode === "orderable" && !item?.ready_admin_notified_at;
      if (retryable && recentStatusChange && (needsUserStatus || needsReadyAdmin)) notifyOrderStatus(item.id);
    });
  }

  async function refreshExpiredTradeLocks() {
    try {
      const changed = await rpc("sq_admin_refresh_trade_locks");
      (changed || []).forEach((item) => notifyOrderStatus(item.request_id));
      return changed || [];
    } catch (error) {
      if (!isMissingRpc(error)) console.warn("Trade-lock refresh failed", error);
      return [];
    }
  }

  async function loadAll({ trigger = null } = {}) {
    if (state.loading) return;
    state.loading = true;
    const refresh = trigger || $("#refreshAdmin");
    refresh?.classList.add("is-loading");
    if (refresh) refresh.disabled = true;
    setSyncState("loading", "Refreshing…");

    let failed = false;
    await refreshExpiredTradeLocks();
    try {
      await loadAdminDirectory();
    } catch (error) {
      failed = true;
      console.error("Admin directory failed", error);
    }

    const tasks = [loadKpis(), loadOrders({ reset: true }), loadSupport({ reset: true }), loadUsers({ reset: true }), loadRewards({ reset: true }), loadPricingDashboard(), loadSystemStatus(), loadPromos(), loadAudit()];
    if (state.owner) tasks.push(loadCoinHistory());
    const results = await Promise.allSettled(tasks);
    if (results.some((item) => item.status === "rejected")) failed = true;
    renderOverview();
    updateNavCounts();
    if (failed) setSyncState("error", "Some data unavailable");
    else updateLastSynced();

    state.loading = false;
    refresh?.classList.remove("is-loading");
    if (refresh) refresh.disabled = false;
  }

  async function loadAdminDirectory() {
    try {
      state.admins = await rpc("sq_admin_directory");
      (state.admins || []).forEach((item) => state.profileMap.set(item.user_id, {
        ...(state.profileMap.get(item.user_id) || {}),
        id: item.user_id,
        email: item.email,
        username: item.username,
        steam_name: item.steam_name
      }));
    } catch (error) {
      if (!isMissingRpc(error)) {
        if ($("#adminUsersList")) $("#adminUsersList").innerHTML = `<div class="admin-empty"><strong>Admin directory unavailable</strong>${safe(error.message)}</div>`;
        throw error;
      }
      const fallback = await sb.from("admin_users").select("user_id,role,created_at").order("role", { ascending: false }).order("created_at", { ascending: true });
      if (fallback.error) throw fallback.error;
      state.admins = fallback.data || [];
      await hydrateProfiles(state.admins.map((item) => item.user_id));
    }
    renderTeam();
  }

  async function loadKpis() {
    try {
      state.kpis = await rpc("sq_admin_kpis");
      renderKpis();
      updateNavCounts();
    } catch (error) {
      if ($("#adminKpis")) $("#adminKpis").innerHTML = `<div class="admin-empty"><strong>Overview unavailable</strong>${safe(error.message)}</div>`;
      throw error;
    }
  }

  function renderKpis() {
    const target = $("#adminKpis");
    if (!target) return;
    const kpi = state.kpis || {};
    const cards = [
      ["Open orders", kpi.open_rewards, "Awaiting fulfilment", "orders", true],
      ["Open support", kpi.open_support, "New or active tickets", "support", true],
      ["Active rewards", kpi.active_rewards, "Visible in the shop", "rewards", false],
      ["Users", kpi.users, `${formatNumber(kpi.new_users_24h)} new in 24h`, "users", false],
      ["Coin liability", kpi.coin_liability, "Coins held by users", state.owner ? "coins" : null, false],
      ["Completed", kpi.completed_rewards, "Reward orders delivered", "orders", false]
    ];
    target.innerHTML = cards.map(([label, value, detail, view, priority]) => `
      <button class="admin-kpi-card ${priority && Number(value || 0) > 0 ? "is-priority" : ""}" type="button" ${view ? `data-admin-view="${view}"` : "disabled"}>
        <span>${safe(label)}</span><strong>${formatNumber(value)}</strong><small>${safe(detail)}</small>
      </button>`).join("");
  }

  async function searchOrders(queryText, status, limit, offset) {
    try {
      return await rpc("sq_admin_search_redemptions", {
        p_query: textValue(queryText) || null,
        p_status: status || "open",
        p_limit: limit,
        p_offset: offset
      });
    } catch (error) {
      if (!isMissingRpc(error)) throw error;
      return fallbackOrderSearch(queryText, status, limit, offset);
    }
  }

  async function fallbackOrderSearch(queryText, status, limit, offset) {
    let query = sb.from("redemption_requests").select("*").order("created_at", { ascending: false });
    if (status === "open") query = query.in("status", ["pending", "reviewing", "ordered", "trade_locked", "ready_to_trade", "trade_sent"]);
    else if (status && status !== "all") query = query.eq("status", status);
    const search = textValue(queryText).toLowerCase();
    if (!search) query = query.range(offset, offset + limit - 1);
    else query = query.limit(500);
    const { data, error } = await query;
    if (error) throw error;
    if (!search) return data || [];
    return (data || []).filter((item) => [orderNumber(item), item.id, item.reward_name, item.user_id, item.admin_note].some((value) => String(value || "").toLowerCase().includes(search))).slice(offset, offset + limit);
  }

  async function loadOrders({ reset = false, append = false } = {}) {
    const target = $("#adminRequests");
    if (!target) return;
    if (reset) state.orderOffset = 0;
    const offset = append ? state.orders.length : state.orderOffset;
    if (!append) target.innerHTML = '<div class="admin-empty">Loading orders…</div>';
    const search = $("#redeemSearch")?.value || "";
    const status = $("#adminStatusFilter")?.value || "open";

    try {
      const rows = await searchOrders(search, status, PAGE_SIZE, offset);
      if (append) state.orders = [...state.orders, ...(rows || [])];
      else state.orders = rows || [];
      state.orderOffset = state.orders.length;
      await hydrateProfiles(state.orders.flatMap((item) => [item.user_id, item.completed_by, item.last_handled_by]));
      renderOrders();
      updateNavCounts();
      retryPendingOrderNotifications(state.orders);
    } catch (error) {
      target.innerHTML = `<div class="admin-empty"><strong>Could not load orders</strong>${safe(error.message)}</div>`;
      throw error;
    }
  }

  function renderOrders() {
    const target = $("#adminRequests");
    if (!target) return;
    renderCaseTable(target, state.orders, "order");
    const count = $("#adminOrderResultCount");
    if (count) count.textContent = `${formatNumber(state.orders.length)} order${state.orders.length === 1 ? "" : "s"} shown`;
    $("#ordersLoadMore")?.classList.toggle("hidden", state.orders.length === 0 || state.orders.length % PAGE_SIZE !== 0);
  }

  async function searchSupport(queryText, status, limit, offset) {
    try {
      return await rpc("sq_admin_search_support", {
        p_query: textValue(queryText) || null,
        p_status: status || "open",
        p_limit: limit,
        p_offset: offset
      });
    } catch (error) {
      if (!isMissingRpc(error)) throw error;
      return fallbackSupportSearch(queryText, status, limit, offset);
    }
  }

  async function fallbackSupportSearch(queryText, status, limit, offset) {
    let query = sb.from("support_requests").select("*").order("created_at", { ascending: false });
    if (status === "open") query = query.in("status", ["new", "open"]);
    else if (status && status !== "all") query = query.eq("status", status);
    const search = textValue(queryText).toLowerCase();
    if (!search) query = query.range(offset, offset + limit - 1);
    else query = query.limit(500);
    const { data, error } = await query;
    if (error) throw error;
    if (!search) return data || [];
    return (data || []).filter((item) => [ticketNumber(item), item.id, item.topic, item.message, item.account_email, item.user_id, item.admin_note].some((value) => String(value || "").toLowerCase().includes(search))).slice(offset, offset + limit);
  }

  async function loadSupport({ reset = false, append = false } = {}) {
    const target = $("#adminSupportRequests");
    if (!target) return;
    if (reset) state.supportOffset = 0;
    const offset = append ? state.support.length : state.supportOffset;
    if (!append) target.innerHTML = '<div class="admin-empty">Loading tickets…</div>';
    const search = $("#supportSearch")?.value || "";
    const status = $("#adminSupportStatusFilter")?.value || "open";

    try {
      const rows = await searchSupport(search, status, PAGE_SIZE, offset);
      if (append) state.support = [...state.support, ...(rows || [])];
      else state.support = rows || [];
      state.supportOffset = state.support.length;
      await hydrateProfiles(state.support.flatMap((item) => [item.user_id, item.resolved_by, item.last_handled_by]));
      renderSupport();
      updateNavCounts();
    } catch (error) {
      target.innerHTML = `<div class="admin-empty"><strong>Could not load support</strong>${safe(error.message)}</div>`;
      throw error;
    }
  }

  function renderSupport() {
    const target = $("#adminSupportRequests");
    if (!target) return;
    renderCaseTable(target, state.support, "support");
    const count = $("#adminSupportResultCount");
    if (count) count.textContent = `${formatNumber(state.support.length)} ticket${state.support.length === 1 ? "" : "s"} shown`;
    $("#supportLoadMore")?.classList.toggle("hidden", state.support.length === 0 || state.support.length % PAGE_SIZE !== 0);
  }

  async function searchUsers(queryText, limit, offset) {
    return rpc("sq_admin_users_activity", {
      p_query: textValue(queryText) || null,
      p_limit: limit,
      p_offset: offset
    });
  }

  async function loadUsers({ reset = false, append = false } = {}) {
    const target = $("#adminUserList");
    if (!target) return;
    if (append && state.userLoading) return;
    const requestId = ++state.userRequestId;
    state.userLoading = true;
    if (!append) target.innerHTML = '<div class="admin-empty">Loading users…</div>';
    const more = $("#usersLoadMore");
    if (more) { more.disabled = true; more.textContent = "Loading…"; }
    try {
      const offset = append ? state.users.length : 0;
      const result = await rpc("sq_admin_users_activity", {
        p_query: textValue($("#adminUserSearch")?.value) || null,
        p_role: $("#adminUserRole")?.value || "all",
        p_login: $("#adminUserLogin")?.value || "all",
        p_sort: $("#adminUserSort")?.value || "newest",
        p_limit: PAGE_SIZE, p_offset: offset
      });
      if (requestId !== state.userRequestId) return;
      const rows = Array.isArray(result?.items) ? result.items : [];
      state.users = append ? [...state.users, ...rows] : rows;
      state.userTotal = Number(result?.total ?? state.users.length);
      state.users.forEach((item) => state.profileMap.set(item.user_id, {
        ...(state.profileMap.get(item.user_id) || {}),
        id: item.user_id,
        email: item.email,
        username: item.username,
        steam_name: item.steam_name,
        contact_email: item.contact_email,
        contact_email_verified_at: item.contact_email_verified_at
      }));
      renderUsers();
    } catch (error) {
      if (requestId !== state.userRequestId) return;
      target.innerHTML = `<div class="admin-empty"><strong>Could not load users</strong>${safe(error.message)}</div>`;
      throw error;
    } finally {
      if (requestId === state.userRequestId) state.userLoading = false;
      if (more && requestId === state.userRequestId) { more.disabled = false; more.textContent = "Load more users"; }
    }
  }

  function userDisplayName(item) {
    return textValue(item.steam_name) || textValue(item.username) || textValue(item.contact_email) || textValue(item.email) || shortId(item.user_id);
  }

  function renderUserTable(target, rows) {
    if (!rows?.length) {
      target.innerHTML = '<div class="admin-empty"><strong>No users found</strong>Try another search or filter.</div>';
      return;
    }
    target.innerHTML = `<div class="admin-directory-header"><span></span><span>User / role</span><span>Date created</span><span>Last active</span><span>Coins</span><span></span></div>${rows.map((item) => `
      <div class="admin-directory-row">
        <span class="admin-account-avatar">${safe((userDisplayName(item)[0] || "U").toUpperCase())}</span>
        <div class="admin-directory-name"><strong>${safe(userDisplayName(item))}</strong><small>${safe(item.contact_email || item.email || "No verified email")}</small><small>${safe(statusLabel(item.role || "user"))} · ${safe(statusLabel(item.account_status))}</small></div>
        <span data-directory-created title="${safe(formatDateTime(item.account_created_at))}">${safe(item.account_created_at ? new Date(item.account_created_at).toLocaleDateString() : "Unknown")}</span>
        <span data-directory-active title="${safe(formatDateTime(item.last_active_at))}">${safe(item.last_active_at ? relativeTime(item.last_active_at) : "Unknown")}</span>
        <span class="admin-stock-value"><b>${formatNumber(item.points_balance)}</b> coins</span>
        <button class="admin-row-action" type="button" data-view-user="${safe(item.user_id)}">View user</button>
      </div>`).join("")}`;
    $$("[data-view-user]", target).forEach((button) => button.addEventListener("click", () => openUserProfile(button.dataset.viewUser)));
  }

  async function openUserProfile(id) {
    if (!id) return;
    const requestId = ++state.userProfileRequestId;
    ++state.userHistoryRequestId;
    state.userHistoryLoading = false;
    state.userProfileId = id;
    state.userHistorySection = "orders";
    state.userHistoryItems = [];
    showView("user");
    $("#adminUserProfile").innerHTML = '<div class="admin-empty">Loading user account…</div>';
    $("#adminUserHistory").innerHTML = "";
    $("#adminUserHistoryCount").textContent = "";
    $("#userHistoryMore")?.classList.add("hidden");
    try {
      const result = await rpc("sq_admin_user_profile", { p_user_id: id });
      if (requestId !== state.userProfileRequestId) return;
      renderUserProfile(result);
      await loadUserHistory("orders");
    } catch (error) {
      if (requestId !== state.userProfileRequestId) return;
      $("#adminUserProfile").innerHTML = `<div class="admin-empty"><strong>User account unavailable</strong>${safe(error.message)}</div>`;
    }
  }

  function renderUserProfile(result) {
    const item = result.user;
    const cpx = result.cpx || {};
    const metric = (value) => value == null ? "No records" : formatNumber(value);
    $("#adminUserProfile").innerHTML = `
      <div class="admin-user-profile-head"><div><p class="admin-eyebrow">User account</p><h2>${safe(userDisplayName(item))}</h2><p>${safe(item.contact_email || item.email || "No verified email")}</p></div>${statusPill(item.account_status || "active")}</div>
      <div class="admin-user-profile-meta">
        <div><span>Role / sign-in</span><strong>${safe(statusLabel(item.role))} · ${item.steam_login ? "Steam sign-in" : "Other sign-in"}</strong></div>
        <div><span>Date created</span><strong>${safe(formatDateTime(item.account_created_at))}</strong></div>
        <div><span>Last active</span><strong>${safe(item.last_active_at ? formatDateTime(item.last_active_at) : "Unknown")}</strong></div>
        <div><span>Steam account</span><strong>${safe(item.steam_name || "Not connected")}</strong><small>${safe(item.steam_id || "")}</small></div>
        <div><span>User ID</span><code>${safe(item.user_id)}</code><button class="admin-text-button" type="button" data-copy-profile-id>Copy ID</button></div>
      </div>
      <div class="admin-user-profile-stats">
        <div><strong>${formatNumber(item.points_balance)}</strong><span>Current coins</span></div>
        <div><strong>${formatNumber(item.order_count)}</strong><span>Orders · ${formatNumber(item.completed_count)} completed</span></div>
        <div><strong>${formatNumber(item.support_count)}</strong><span>Support tickets</span></div>
      </div>
      <details class="admin-user-cpx"><summary>CPX activity &amp; data status</summary><div class="admin-user-profile-stats">
        <div><strong>${metric(cpx.completed_reward_events)}</strong><span>Completed reward postbacks</span></div>
        <div><strong>${metric(cpx.ledger_credit_rows)}</strong><span>CPX-labelled ledger credits</span></div>
        <div><strong>${metric(cpx.logged_opens)}</strong><span>Logged CPX launch clicks</span></div>
      </div><p>${safe(cpx.note)}</p>${!cpx.postback_rows ? '<p>No CPX postbacks are recorded for this account. Check coin history for legacy credits; this does not prove the user completed zero surveys.</p>' : ""}${cpx.logged_opens == null ? '<p>No launch clicks recorded. Individual survey launches inside the CPX widget cannot be counted here.</p>' : ""}</details>`;
    $("[data-copy-profile-id]")?.addEventListener("click", () => copyToClipboard(item.user_id, "User ID copied."));
  }

  async function loadUserHistory(section = state.userHistorySection, append = false) {
    if (!state.userProfileId) return;
    if (append && state.userHistoryLoading) return;
    const requestId = ++state.userHistoryRequestId;
    state.userHistoryLoading = true;
    state.userHistorySection = section;
    $$("[data-user-history-section]").forEach((button) => {
      const active = button.dataset.userHistorySection === section;
      button.classList.toggle("active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    const target = $("#adminUserHistory");
    if (!append) {
      state.userHistoryItems = [];
      target.innerHTML = '<div class="admin-empty">Loading history…</div>';
    }
    $("#userHistoryMore")?.classList.add("hidden");
    try {
      const result = await rpc("sq_admin_user_records", {
        p_user_id: state.userProfileId, p_section: section, p_limit: 25,
        p_offset: append ? state.userHistoryItems.length : 0
      });
      if (requestId !== state.userHistoryRequestId) return;
      state.userHistoryItems = append ? [...state.userHistoryItems, ...result.items] : result.items;
      state.userHistoryTotal = Number(result.total || 0);
      renderUserHistory();
    } catch (error) {
      if (requestId !== state.userHistoryRequestId) return;
      target.innerHTML = `<div class="admin-empty"><strong>History unavailable</strong>${safe(error.message)}</div>`;
    } finally {
      if (requestId === state.userHistoryRequestId) state.userHistoryLoading = false;
    }
  }

  function renderUserHistory() {
    const section = state.userHistorySection;
    const rows = state.userHistoryItems;
    $("#adminUserHistoryCount").textContent = `Showing ${formatNumber(rows.length)} of ${formatNumber(state.userHistoryTotal)}`;
    $("#userHistoryMore")?.classList.toggle("hidden", rows.length >= state.userHistoryTotal);
    $("#adminUserHistory").innerHTML = rows.length ? rows.map((item) => {
      let title = "", detail = "", value = "", action = "";
      const date = item.redeemed_at || item.created_at;
      if (section === "orders") {
        title = orderRewardLabel(item);
        detail = `${orderNumber(item)} · ${statusLabel(item.status)}`;
        value = `${formatNumber(item.points_coins || item.points_cost)} coins`;
        action = `<button class="admin-row-action" type="button" data-profile-order="${safe(item.id)}">Open order</button>`;
      } else if (section === "support") {
        title = item.topic || "Support request";
        detail = `${ticketNumber(item)} · ${statusLabel(item.status)}`;
        action = `<button class="admin-row-action" type="button" data-profile-support="${safe(item.id)}">Open ticket</button>`;
      } else if (section === "coins") {
        title = item.reason || "Coin adjustment";
        detail = item.source_type ? statusLabel(item.source_type) : "Legacy ledger entry";
        value = `${Number(item.amount)>0 ? "+" : ""}${formatNumber(item.amount)} coins`;
      } else if (section === "promos") {
        title = item.code_snapshot || "Unknown legacy code";
        detail = `${item.campaign_snapshot || "No campaign"}${item.promo_code_id == null ? " · Deleted code" : ""}`;
        value = `+${formatNumber(item.coins_awarded)} coins`;
      } else {
        title = `${String(item.provider || "Provider").toUpperCase()} · ${item.provider_event_id || item.id}`;
        detail = statusLabel(item.status);
        value = `${formatNumber(item.amount)} coins`;
      }
      return `<div class="admin-user-history-row"><div><strong>${safe(title)}</strong><small>${safe(detail)}</small><small>${safe(formatDateTime(date))}</small></div><span>${safe(value)}</span>${action}</div>`;
    }).join("") : '<div class="admin-empty"><strong>No recorded entries</strong>No entries exist in this history section; missing provider logs are not proof of zero survey activity.</div>';
    $$("[data-profile-order]").forEach((button) => button.addEventListener("click", () => openOrder(Number(button.dataset.profileOrder))));
    $$("[data-profile-support]").forEach((button) => button.addEventListener("click", () => openSupport(Number(button.dataset.profileSupport))));
  }

  function renderUsers() {
    const target = $("#adminUserList");
    if (!target) return;
    renderUserTable(target, state.users);
    if ($("#adminUserResultCount")) $("#adminUserResultCount").textContent = state.userTotal
      ? `Showing ${formatNumber(state.users.length)} of ${formatNumber(state.userTotal)}`
      : "No matching users";
    $("#usersLoadMore")?.classList.toggle("hidden", state.users.length >= state.userTotal);
  }

  function renderCaseTable(target, items, type) {
    if (!items?.length) {
      target.innerHTML = `<div class="admin-empty"><strong>No ${type === "order" ? "orders" : "tickets"} found</strong>Try another search or status filter.</div>`;
      return;
    }
    const isOrder = type === "order";
    target.innerHTML = `
      <div class="admin-case-header" role="row">
        <span>${isOrder ? "Order" : "Ticket"}</span><span>${isOrder ? "Reward / customer" : "Topic / customer"}</span><span>${isOrder ? "Placed" : "Received"}</span><span>${isOrder ? "Coins" : "Channel"}</span><span>Status</span><span>${isOrder ? "Handled by" : "Resolved by"}</span><span></span>
      </div>
      ${items.map((item) => {
        const number = isOrder ? orderNumber(item) : ticketNumber(item);
        const primary = isOrder ? orderRewardLabel(item) : item.topic;
        const customer = isOrder ? profileLabel(item.user_id) : (item.account_email || profileLabel(item.user_id));
        const value = isOrder ? formatNumber(item.points_coins || item.points_cost) : "Web form";
        const handler = isOrder ? (item.completed_by || item.last_handled_by) : (item.resolved_by || item.last_handled_by);
        return `<button class="admin-case-row" type="button" data-open-${isOrder ? "order" : "support"}="${safe(item.id)}" aria-label="Open ${safe(number)}">
          <span class="admin-case-number">${safe(number)}</span>
          <div><strong>${safe(primary || (isOrder ? "Reward order" : "Support request"))}</strong><small>${safe(customer)}</small></div>
          <span class="admin-case-date">${safe(formatShortDate(item.created_at))}<small>${safe(relativeTime(item.created_at))}</small></span>
          <span class="admin-case-value">${safe(value)}</span>
          ${statusPill(item.status || (isOrder ? "pending" : "new"))}
          <span class="admin-case-handler">${safe(handler ? adminLabel(handler) : "Unassigned")}</span>
          <svg class="admin-case-arrow" viewBox="0 0 24 24"><path d="m9 6 6 6-6 6"/></svg>
        </button>`;
      }).join("")}`;

    $$(`[data-open-${isOrder ? "order" : "support"}]`, target).forEach((button) => {
      button.addEventListener("click", () => isOrder ? openOrder(Number(button.dataset.openOrder)) : openSupport(Number(button.dataset.openSupport)));
    });
  }

  async function executeGlobalSearch(rawQuery) {
    const query = textValue(rawQuery);
    if (query.length < 2) return notify("Enter at least 2 characters to search all records.", "error");
    const target = $("#adminSearchResults");
    if (!target) return;
    showView("search");
    target.innerHTML = '<div class="admin-empty">Searching users, orders, and support tickets…</div>';
    if ($("#adminSearchSummary")) $("#adminSearchSummary").textContent = `Results for “${query}”`;

    try {
      const [usersResult, orders, support] = await Promise.all([
        searchUsers(query, 50, 0),
        searchOrders(query, "all", 50, 0),
        searchSupport(query, "all", 50, 0)
      ]);
      state.globalUsers = Array.isArray(usersResult?.items) ? usersResult.items : [];
      state.globalOrders = orders || [];
      state.globalSupport = support || [];
      state.globalUsers.forEach((item) => state.profileMap.set(item.user_id, {
        ...(state.profileMap.get(item.user_id) || {}),
        id: item.user_id,
        email: item.email,
        username: item.username,
        steam_name: item.steam_name,
        contact_email: item.contact_email,
        contact_email_verified_at: item.contact_email_verified_at
      }));
      await hydrateProfiles([...state.globalOrders.flatMap((item) => [item.user_id, item.completed_by, item.last_handled_by]), ...state.globalSupport.flatMap((item) => [item.user_id, item.resolved_by, item.last_handled_by])]);
      const total = state.globalUsers.length + state.globalOrders.length + state.globalSupport.length;
      if ($("#adminSearchSummary")) $("#adminSearchSummary").textContent = `${formatNumber(total)} result${total === 1 ? "" : "s"} for “${query}”`;
      if (!total) {
        target.innerHTML = '<div class="admin-card"><div class="admin-empty"><strong>No matching records</strong>Check the email, Steam name, number, reward, topic, or user ID and try again.</div></div>';
        return;
      }
      target.innerHTML = `
        ${state.globalUsers.length ? '<section class="admin-search-group"><h2>Users</h2><div class="admin-card admin-table-card" data-global-user-results></div></section>' : ""}
        ${state.globalOrders.length ? '<section class="admin-search-group"><h2>Reward orders</h2><div class="admin-card admin-table-card" data-global-order-results></div></section>' : ""}
        ${state.globalSupport.length ? '<section class="admin-search-group"><h2>Support tickets</h2><div class="admin-card admin-table-card" data-global-support-results></div></section>' : ""}`;
      if (state.globalUsers.length) renderUserTable($("[data-global-user-results]", target), state.globalUsers);
      if (state.globalOrders.length) renderCaseTable($("[data-global-order-results]", target), state.globalOrders, "order");
      if (state.globalSupport.length) renderCaseTable($("[data-global-support-results]", target), state.globalSupport, "support");
    } catch (error) {
      target.innerHTML = `<div class="admin-card"><div class="admin-empty"><strong>Search unavailable</strong>${safe(error.message)}</div></div>`;
    }
  }

  function renderOverview() {
    renderPriorityQueue();
    renderOverviewHealth();
    renderOverviewAudit();
  }

  function renderPriorityQueue() {
    const target = $("#adminPriorityQueue");
    if (!target) return;
    const orderRows = state.orders.filter((item) => ["pending", "reviewing", "ordered", "trade_locked", "ready_to_trade", "trade_sent"].includes(item.status)).map((item) => ({ ...item, caseType: "order", number: orderNumber(item), title: orderRewardLabel(item), customer: profileLabel(item.user_id) }));
    const supportRows = state.support.filter((item) => ["new", "open", null].includes(item.status)).map((item) => ({ ...item, caseType: "support", number: ticketNumber(item), title: item.topic, customer: item.account_email || profileLabel(item.user_id) }));
    const rows = [...orderRows, ...supportRows].sort((a, b) => new Date(a.created_at) - new Date(b.created_at)).slice(0, 7);
    if (!rows.length) {
      target.innerHTML = '<div class="admin-empty"><strong>Queue clear</strong>No open orders or support tickets need attention.</div>';
      return;
    }
    target.innerHTML = rows.map((item) => `<button class="admin-compact-row" type="button" data-queue-type="${item.caseType}" data-queue-id="${safe(item.id)}">
      <span><span class="admin-case-kind">${item.caseType === "order" ? "Redeem order" : "Support"}</span><strong class="admin-case-number">${safe(item.number)}</strong></span>
      <span><strong>${safe(item.title || "Untitled case")}</strong><small>${safe(item.customer)}</small></span>
      <span><small>${safe(relativeTime(item.created_at))}</small></span>
      ${statusPill(item.status || "new")}
    </button>`).join("");
    $$('[data-queue-type]', target).forEach((button) => button.addEventListener("click", () => button.dataset.queueType === "order" ? openOrder(Number(button.dataset.queueId)) : openSupport(Number(button.dataset.queueId))));
  }

  function renderOverviewHealth() {
    const target = $("#adminOverviewHealth");
    if (!target) return;
    if (!state.statuses.length) {
      target.innerHTML = '<div class="admin-empty">No status components available.</div>';
      return;
    }
    target.innerHTML = state.statuses.map((item) => `<div class="admin-health-row" data-status="${safe(item.status)}"><i class="admin-health-dot"></i><div><strong>${safe(item.display_name)}</strong><small>${safe(statusLabel(item.status))} · ${safe(item.message || "No public message")}</small></div></div>`).join("");
  }

  function renderOverviewAudit() {
    const target = $("#adminOverviewAudit");
    if (!target) return;
    const rows = state.audit.slice(0, 6);
    if (!rows.length) {
      target.innerHTML = '<div class="admin-empty">No admin activity recorded yet.</div>';
      return;
    }
    target.innerHTML = rows.map((row) => `<div class="admin-compact-row admin-audit-overview-row"><span><span class="admin-case-kind">${safe(adminLabel(row.actor_user_id))}</span><strong>${safe(auditActionLabel(row.action))}</strong></span><span><strong>${safe(auditEntityLabel(row))}</strong><small>${safe(auditDetail(row))}</small></span><span><small>${safe(relativeTime(row.created_at))}</small></span><svg class="admin-case-arrow" viewBox="0 0 24 24"><path d="m9 6 6 6-6 6"/></svg></div>`).join("");
  }

  function openDrawer(html, { type, id }) {
    state.lastFocus = document.activeElement;
    state.activeDrawer = { type, id };
    const backdrop = $("#adminDrawerBackdrop");
    if ($("#adminDrawerContent")) $("#adminDrawerContent").innerHTML = html;
    backdrop?.classList.remove("hidden");
    backdrop?.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
    window.setTimeout(() => $("[data-close-admin-drawer]")?.focus(), 30);
  }

  function closeDrawer() {
    const backdrop = $("#adminDrawerBackdrop");
    if (!backdrop || backdrop.classList.contains("hidden")) return;
    backdrop.classList.add("hidden");
    backdrop.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    state.activeDrawer = null;
    state.lastFocus?.focus?.();
  }

  async function findOrder(id) {
    const local = [...state.orders, ...state.globalOrders].find((item) => Number(item.id) === Number(id));
    if (local) return local;
    const { data, error } = await sb.from("redemption_requests").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return data;
  }

  async function findSupport(id) {
    const local = [...state.support, ...state.globalSupport].find((item) => Number(item.id) === Number(id));
    if (local) return local;
    const { data, error } = await sb.from("support_requests").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return data;
  }

  async function openOrder(id) {
    try {
      const item = await findOrder(id);
      if (!item) return notify("Order not found.", "error");
      await hydrateProfiles([item.user_id, item.completed_by, item.last_handled_by]);
      const number = orderNumber(item);
      const isTerminal = ["completed", "rejected", "refunded", "cancelled"].includes(item.status);
      openDrawer(`
        <div class="admin-drawer-head"><p class="admin-eyebrow">Reward order</p><h2 id="adminDrawerTitle">${safe(number)}</h2><p>${safe(orderRewardLabel(item))}</p></div>
        <div class="admin-drawer-meta">
          <div><span>Status</span>${statusPill(item.status)}</div><div><span>Customer</span><strong>${safe(profileLabel(item.user_id))}</strong></div>
          <div><span>Created</span><strong>${safe(formatDateTime(item.created_at))}</strong></div><div><span>Value</span><strong>${formatNumber(item.points_coins || item.points_cost)} coins</strong></div>
          <div><span>Fulfilment</span><strong>${item.fulfillment_mode === "orderable" ? "Available to order" : "In stock / prepared"}</strong></div><div><span>Trade lock</span><strong>${item.trade_locked_until ? `${safe(tradeLockRemaining(item.trade_locked_until))} · ${safe(formatDateTime(item.trade_locked_until))}` : "Not set"}</strong></div>
          <div><span>Last handled by</span><strong>${safe(item.last_handled_by ? adminLabel(item.last_handled_by) : "Not handled")}</strong></div><div><span>Completed by</span><strong>${safe(item.completed_by ? adminLabel(item.completed_by) : "Not completed")}</strong></div>
        </div>
        <section class="admin-drawer-section"><h3>Customer Steam trade URL</h3><div class="admin-copy-block"><code title="${safe(item.steam_trade_url || "")}">${safe(item.steam_trade_url || "No trade URL saved")}</code><button class="admin-row-action" type="button" data-copy-drawer="trade">Copy</button><button class="admin-row-action" type="button" data-open-trade ${item.steam_trade_url ? "" : "disabled"}>Open</button></div></section>
        <section class="admin-drawer-section"><h3>Update fulfilment</h3><form class="admin-drawer-form" id="adminOrderUpdateForm">
          ${isTerminal ? '<div class="admin-terminal-notice">This order is final. Notes and proof can still be documented, but its status cannot be reopened.</div>' : ""}
          <label>Status<select id="drawerOrderStatus" ${isTerminal ? "disabled" : ""}>${allowedOrderStatuses(item).map((status) => `<option value="${status}" ${status === item.status ? "selected" : ""}>${safe(statusLabel(status))}</option>`).join("")}</select><small>Only safe next steps are shown. Sent trades cannot be refunded from the normal workflow.</small></label>
          <label>Trade lock ends<input id="drawerOrderLockUntil" type="datetime-local" value="${safe(toLocalDateTimeInput(item.trade_locked_until))}" ${(isTerminal || item.fulfillment_mode !== "orderable") ? "disabled" : ""} /><small>${item.fulfillment_mode === "orderable" ? "After purchase, enter Steam's exact tradable time. The customer sees a live countdown." : "Prepared rewards do not use the purchase trade-lock stage."}</small></label>
          <label>Steam trade offer URL (optional)<input id="drawerOrderTrade" maxlength="500" value="${safe(item.trade_offer_url || "")}" placeholder="https://steamcommunity.com/tradeoffer/123456789/" /><small>Leave blank if Steam does not provide a link. Confirm the offer was actually sent before choosing Trade sent.</small></label>
          <label>Admin note<textarea id="drawerOrderNote" maxlength="2000" placeholder="Internal context or a customer-visible update">${safe(item.admin_note || "")}</textarea></label>
          <div class="admin-quick-actions">${allowedOrderStatuses(item).filter((status) => status !== item.status && !["rejected","refunded","cancelled"].includes(status)).map((status) => `<button class="admin-secondary-button" type="button" data-order-quick="${safe(status)}">${safe(status === "trade_locked" ? "Purchased / trade locked" : statusLabel(status))}</button>`).join("")}</div>
          <div class="admin-drawer-actions"><button class="admin-secondary-button" type="button" data-copy-order-message>Copy customer update</button><button class="admin-primary-button" type="submit">Save order</button></div>
        </form></section>
        <section class="admin-drawer-section"><h3>Case history</h3><div class="admin-timeline" id="adminCaseTimeline"><div class="admin-empty">Loading history…</div></div></section>
      `, { type: "order", id: item.id });

      $("[data-copy-drawer=trade]")?.addEventListener("click", () => copyToClipboard(item.steam_trade_url || "", "Trade URL copied."));
      $("[data-open-trade]")?.addEventListener("click", () => openTrustedUrl(item.steam_trade_url));
      $("#adminOrderUpdateForm")?.addEventListener("submit", (event) => saveOrderUpdate(event, item));
      $$('[data-order-quick]').forEach((button) => button.addEventListener("click", () => {
        if ($("#drawerOrderStatus")) $("#drawerOrderStatus").value = button.dataset.orderQuick;
        $("#adminOrderUpdateForm")?.requestSubmit();
      }));
      $("[data-copy-order-message]")?.addEventListener("click", () => {
        const status = $("#drawerOrderStatus")?.value || item.status;
        const message = `Hi,\n\nYour SkinQuest reward order ${number} for ${item.reward_name} has been updated to ${statusLabel(status)}. Please check your SkinQuest dashboard for details.\n\nBest regards,\nSkinQuest Support`;
        copyToClipboard(message, "Customer update copied.");
      });
      loadCaseTimeline("redemption_request", item.id, item);
    } catch (error) {
      notify(error.message || "Could not open the order.", "error");
    }
  }

  async function saveOrderUpdate(event, item) {
    event.preventDefault();
    const form = event.currentTarget;
    const button = $('button[type="submit"]', form);
    const status = $("#drawerOrderStatus")?.value;
    const note = textValue($("#drawerOrderNote")?.value);
    const trade = textValue($("#drawerOrderTrade")?.value);
    const lockInput = textValue($("#drawerOrderLockUntil")?.value);
    const lockUntil = lockInput ? new Date(lockInput) : null;
    if (!ORDER_STATUSES.includes(status)) return notify("Choose a valid order status.", "error");
    if (!allowedOrderStatuses(item).includes(status)) return notify(`You cannot move this order from ${statusLabel(item.status)} to ${statusLabel(status)}.`, "error");
    if (trade && !isValidTradeProof(trade)) return notify("Use a Steam trade-offer URL like https://steamcommunity.com/tradeoffer/123456789/.", "error");
    if (status === "trade_locked" && item.fulfillment_mode !== "orderable") return notify("Prepared rewards do not use Trade locked.", "error");
    if (status === "trade_locked" && (!lockUntil || Number.isNaN(lockUntil.getTime()) || lockUntil.getTime() <= Date.now())) return notify("Set a future Steam trade-lock end time first.", "error");

    if (status === "completed" && item.status !== "trade_sent") return notify("Mark the Steam trade as sent before completing the order.", "error");
    if (status === "trade_sent" && item.status !== "trade_sent") {
      const confirmed = await confirmAction("Confirm that you actually sent the Steam trade offer. This order cannot be refunded through the normal workflow after this step.", { title: "Mark trade sent?", confirmText: "Trade was sent", cancelText: "Cancel", icon: "↗" });
      if (!confirmed) return;
    }

    if (["rejected", "refunded", "cancelled"].includes(status) && status !== item.status) {
      const stockEffect = item.fulfillment_mode === "orderable" ? " Prepared stock will not be changed." : " The reserved prepared unit will be released.";
      const confirmed = await confirmAction(`This terminal status refunds the customer's coins once.${stockEffect} It cannot be reopened afterward.`, { title: `Mark ${statusLabel(status)}?`, confirmText: "Confirm refund", cancelText: "Cancel", danger: true, icon: "↩" });
      if (!confirmed) return;
    }
    if (status === "completed" && item.status !== "completed") {
      const stockEffect = item.fulfillment_mode === "orderable" ? " Prepared stock will not be changed." : " One reserved prepared unit will be consumed.";
      const confirmed = await confirmAction(`This finalizes the order.${stockEffect} The completed order cannot be reopened afterward.`, { title: "Complete order?", confirmText: "Mark completed", cancelText: "Cancel", icon: "✓" });
      if (!confirmed) return;
    }

    const restore = buttonBusy(button, "Saving…");
    try {
      await rpc("sq_admin_update_order", {
        p_request_id: item.id,
        p_status: status,
        p_admin_note: note || null,
        p_trade_offer_url: trade || null,
        p_trade_locked_until: lockUntil ? lockUntil.toISOString() : null
      });
      notify(`${orderNumber(item)} updated.`, "success");
      notifyOrderStatus(item.id);
      closeDrawer();
      await Promise.allSettled([loadOrders({ reset: true }), loadKpis(), loadRewards(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not update the order.", "error");
    } finally {
      restore();
    }
  }

  async function openSupport(id) {
    try {
      const item = await findSupport(id);
      if (!item) return notify("Support ticket not found.", "error");
      await hydrateProfiles([item.user_id, item.resolved_by, item.last_handled_by]);
      const number = ticketNumber(item);
      openDrawer(`
        <div class="admin-drawer-head"><p class="admin-eyebrow">Support ticket</p><h2 id="adminDrawerTitle">${safe(number)}</h2><p>${safe(item.topic || "Support request")}</p></div>
        <div class="admin-drawer-meta">
          <div><span>Status</span>${statusPill(item.status || "new")}</div><div><span>Email</span><strong>${safe(item.account_email || "Not captured")}</strong></div>
          <div><span>Received</span><strong>${safe(formatDateTime(item.created_at))}</strong></div><div><span>User</span><strong>${safe(profileLabel(item.user_id))}</strong></div>
          <div><span>Last handled by</span><strong>${safe(item.last_handled_by ? adminLabel(item.last_handled_by) : "Not handled")}</strong></div><div><span>Resolved by</span><strong>${safe(item.resolved_by ? adminLabel(item.resolved_by) : "Not resolved")}</strong></div>
        </div>
        <section class="admin-drawer-section"><h3>Customer message</h3><p class="admin-drawer-copy">${safe(item.message || "No message")}</p></section>
        <section class="admin-drawer-section"><h3>Request context</h3><div class="admin-drawer-meta"><div><span>Page</span><strong title="${safe(item.page_url || "")}">${safe(item.page_url || "Unknown")}</strong></div><div><span>Language</span><strong>${safe(item.browser_language || "Unknown")}</strong></div></div><div class="admin-copy-block"><code title="${safe(item.user_agent || "")}">${safe(item.user_agent || "Browser not captured")}</code><button class="admin-row-action" type="button" data-copy-browser>Copy</button><button class="admin-row-action" type="button" data-open-page ${item.page_url ? "" : "disabled"}>Open page</button></div></section>
        <section class="admin-drawer-section"><h3>Handle ticket</h3><form class="admin-drawer-form" id="adminSupportUpdateForm">
          <label>Status<select id="drawerSupportStatus">${SUPPORT_STATUSES.map((status) => `<option value="${status}" ${status === (item.status || "new") ? "selected" : ""}>${safe(statusLabel(status))}</option>`).join("")}</select></label>
          <label>Internal admin note<textarea id="drawerSupportNote" maxlength="2000" placeholder="What was checked, answered, or resolved">${safe(item.admin_note || "")}</textarea></label>
          <div class="admin-quick-actions"><button class="admin-secondary-button" type="button" data-support-quick="open">Mark open</button><button class="admin-secondary-button" type="button" data-copy-support-email>Copy email</button><button class="admin-secondary-button" type="button" data-support-quick="resolved">Resolve</button></div>
          <div class="admin-drawer-actions"><button class="admin-primary-button" type="submit">Save ticket</button></div>
        </form></section>
        <section class="admin-drawer-section"><h3>Case history</h3><div class="admin-timeline" id="adminCaseTimeline"><div class="admin-empty">Loading history…</div></div></section>
      `, { type: "support", id: item.id });

      $("[data-copy-browser]")?.addEventListener("click", () => copyToClipboard(item.user_agent || "", "Browser details copied."));
      $("[data-open-page]")?.addEventListener("click", () => openSkinQuestUrl(item.page_url));
      $("[data-copy-support-email]")?.addEventListener("click", () => copyToClipboard(item.account_email || "", "Email copied."));
      $("#adminSupportUpdateForm")?.addEventListener("submit", (event) => saveSupportUpdate(event, item));
      $$('[data-support-quick]').forEach((button) => button.addEventListener("click", () => {
        if ($("#drawerSupportStatus")) $("#drawerSupportStatus").value = button.dataset.supportQuick;
        $("#adminSupportUpdateForm")?.requestSubmit();
      }));
      loadCaseTimeline("support_request", item.id, item);
    } catch (error) {
      notify(error.message || "Could not open the ticket.", "error");
    }
  }

  async function saveSupportUpdate(event, item) {
    event.preventDefault();
    const button = $('button[type="submit"]', event.currentTarget);
    const status = $("#drawerSupportStatus")?.value;
    const note = textValue($("#drawerSupportNote")?.value);
    if (!SUPPORT_STATUSES.includes(status)) return notify("Choose a valid support status.", "error");
    if (status === "resolved" && item.status !== "resolved") {
      const confirmed = await confirmAction("This records you as the resolving admin and moves the ticket into history.", { title: "Resolve ticket?", confirmText: "Mark resolved", cancelText: "Cancel", icon: "✓" });
      if (!confirmed) return;
    }

    const restore = buttonBusy(button, "Saving…");
    try {
      await rpc("sq_admin_update_support_status", { p_request_id: item.id, p_status: status, p_admin_note: note || null });
      notify(`${ticketNumber(item)} updated.`, "success");
      closeDrawer();
      await Promise.allSettled([loadSupport({ reset: true }), loadKpis(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not update the support ticket.", "error");
    } finally {
      restore();
    }
  }

  async function loadCaseTimeline(entityType, entityId, item) {
    const target = $("#adminCaseTimeline");
    if (!target) return;
    try {
      const { data, error } = await sb.from("sq_admin_audit_log").select("id,actor_user_id,action,details,created_at").eq("entity_type", entityType).eq("entity_id", String(entityId)).order("created_at", { ascending: true }).limit(100);
      if (error) throw error;
      await hydrateProfiles((data || []).map((row) => row.actor_user_id));
      const rows = [{ title: entityType === "redemption_request" ? "Order created" : "Ticket received", detail: "Created by the customer", time: item.created_at }];
      (data || []).forEach((row) => rows.push({ title: auditActionLabel(row.action), detail: `${adminLabel(row.actor_user_id)} · ${auditDetail(row)}`, time: row.created_at }));
      if (!(data || []).length) {
        if (entityType === "redemption_request" && item.completed_at) rows.push({ title: "Order completed", detail: item.completed_by ? `Completed by ${adminLabel(item.completed_by)}` : "Completed before handler tracking was enabled", time: item.completed_at });
        if (entityType === "support_request" && item.resolved_at) rows.push({ title: "Ticket resolved", detail: item.resolved_by ? `Resolved by ${adminLabel(item.resolved_by)}` : "Resolved before handler tracking was enabled", time: item.resolved_at });
      }
      target.innerHTML = rows.map((row) => `<div class="admin-timeline-row"><i class="admin-timeline-dot"></i><div><strong>${safe(row.title)}</strong><small>${safe(row.detail)} · ${safe(formatDateTime(row.time))}</small></div></div>`).join("");
    } catch (error) {
      target.innerHTML = `<div class="admin-empty">History unavailable: ${safe(error.message)}</div>`;
    }
  }

  function copyToClipboard(value, success) {
    if (typeof window.copyToClipboard === "function") return window.copyToClipboard(value, success);
    return navigator.clipboard.writeText(String(value || "")).then(() => notify(success, "success"));
  }

  function isValidTradeProof(value) {
    try {
      const url = new URL(value);
      const hostOk = ["steamcommunity.com", "www.steamcommunity.com"].includes(url.hostname.toLowerCase());
      return url.protocol === "https:" && hostOk && /^\/tradeoffer\/\d+\/?$/.test(url.pathname);
    } catch { return false; }
  }

  function openTrustedUrl(value) {
    try {
      const url = new URL(value);
      if (url.protocol !== "https:" || !["steamcommunity.com", "www.steamcommunity.com"].includes(url.hostname.toLowerCase()) || url.pathname.replace(/\/$/, "") !== "/tradeoffer/new" || !/^\d+$/.test(url.searchParams.get("partner") || "") || !/^[A-Za-z0-9_-]+$/.test(url.searchParams.get("token") || "")) throw new Error();
      window.open(url.href, "_blank", "noopener,noreferrer");
    } catch { notify("No valid customer Steam trade URL is available.", "error"); }
  }

  function openSkinQuestUrl(value) {
    try {
      const url = new URL(value);
      if (url.protocol !== "https:" || !["skinquestcs.com", "www.skinquestcs.com"].includes(url.hostname.toLowerCase())) throw new Error();
      window.open(url.href, "_blank", "noopener,noreferrer");
    } catch { notify("The recorded page URL is not a trusted SkinQuest address.", "error"); }
  }

  async function loadRewards(options = {}) {
    const target = $("#adminRewardsList");
    if (!target || state.rewardLoading) return;
    const append = options.append === true;
    state.rewardLoading = true;
    if (!append) target.innerHTML = '<div class="admin-empty">Loading rewards…</div>';
    const loadMore = $("#rewardsLoadMore");
    if (loadMore) { loadMore.disabled = true; loadMore.textContent = "Loading…"; }

    try {
      const offset = append ? state.rewards.length : 0;
      const result = await rpc("sq_admin_search_reward_items", {
        p_query: textValue($("#rewardAdminSearch")?.value) || null,
        p_filter: $("#rewardAdminModeFilter")?.value || "all",
        p_sort: $("#rewardAdminSort")?.value || "stock-first",
        p_limit: PAGE_SIZE,
        p_offset: offset
      });
      const rows = Array.isArray(result?.items) ? result.items : [];
      if (append) {
        const merged = new Map(state.rewards.map((item) => [Number(item.id), item]));
        rows.forEach((item) => merged.set(Number(item.id), item));
        state.rewards = Array.from(merged.values());
      } else {
        state.rewards = rows;
      }
      state.rewardOffset = state.rewards.length;
      state.rewardTotal = Number(result?.total ?? state.rewards.length);
    } catch (error) {
      if (!isMissingRpc(error)) {
        target.innerHTML = `<div class="admin-empty"><strong>Could not load rewards</strong>${safe(error.message)}</div>`;
        throw error;
      }
      const fallback = await sb.from("reward_items").select("*").order("active", { ascending: false }).order("sort_order", { ascending: true }).order("points_coins", { ascending: true }).limit(PAGE_SIZE);
      if (fallback.error) throw fallback.error;
      state.rewards = fallback.data || [];
      state.rewardTotal = state.rewards.length;
    } finally {
      state.rewardLoading = false;
    }
    renderRewards();
  }

  function rewardCost(item) {
    return Number(item?.points_coins || item?.points_cost || 0);
  }

  function rewardMode(item) {
    if (rewardStock(item).available > 0) return "stocked";
    return item?.fulfillment_mode === "orderable" ? "orderable" : "stocked";
  }

  function rewardStock(item) {
    const total = Number(item?.quantity_total || 0);
    const reserved = Number(item?.quantity_reserved || 0);
    return { total, reserved, available: Math.max(0, total - reserved) };
  }

  function steamPriceIsCurrent(item) {
    if (item?.pricing_mode !== "steam") return true;
    const validUntil = new Date(item?.steam_price_valid_until || 0).getTime();
    return Number(item?.steam_price_minor || 0) > 0 && Number.isFinite(validUntil) && validUntil > Date.now();
  }

  function formatSteamMoney(item) {
    const minor = Number(item?.steam_price_minor || 0);
    if (!Number.isFinite(minor) || minor <= 0) return "No Steam price";
    try {
      return new Intl.NumberFormat(undefined, { style: "currency", currency: item?.steam_price_currency || "EUR" }).format(minor / 100);
    } catch {
      return `€${(minor / 100).toFixed(2)}`;
    }
  }

  function renderRewardStats() {
    const stats = state.rewardStats || {};
    const target = $("#adminRewardStats");
    if (!target) return;
    target.innerHTML = [
      [stats.active_listings, "active listings"],
      [stats.orderable_listings, "order items"],
      [stats.prepared_units, "prepared units"],
      [stats.reserved_units, "reserved units"],
      [stats.steam_linked, "Steam linked"],
      [stats.stale_prices, "prices to refresh"]
    ].map(([value, label]) => `<span class="admin-mini-stat"><strong>${formatNumber(value || 0)}</strong>${safe(label)}</span>`).join("");
  }

  function renderRewards() {
    const target = $("#adminRewardsList");
    if (!target) return;
    renderRewardStats();
    if ($("#adminRewardResultCount")) $("#adminRewardResultCount").textContent = state.rewardTotal
      ? `Showing ${formatNumber(state.rewards.length)} of ${formatNumber(state.rewardTotal)}`
      : "No matching listings";
    const loadMore = $("#rewardsLoadMore");
    if (loadMore) {
      loadMore.classList.toggle("hidden", state.rewards.length >= state.rewardTotal);
      loadMore.disabled = false;
      loadMore.textContent = "Load more listings";
    }
    if (!state.rewards.length) {
      target.innerHTML = '<div class="admin-empty"><strong>No rewards found</strong>Try another catalog filter or Steam market name.</div>';
      return;
    }
    target.innerHTML = `<div class="admin-reward-header"><span></span><span>Reward</span><span>Price</span><span>Stock</span><span>Visibility</span><span></span></div>${state.rewards.map((item) => {
      const stock = rewardStock(item);
      const image = textValue(item.image_url);
      const linked = item.pricing_mode === "steam";
      const current = steamPriceIsCurrent(item);
      const sourceLabel = linked ? (current ? `${formatSteamMoney(item)} · Steam` : "Steam price refresh needed") : "Manual price";
      const sourceClass = linked ? (current ? "" : "is-stale") : "is-manual";
      const marketName = textValue(item.market_name);
      const marketHref = marketName ? `https://steamcommunity.com/market/listings/730/${encodeURIComponent(marketName)}` : "";
      return `<div class="admin-reward-row ${item.active ? "" : "is-inactive"}">
        <div class="admin-reward-image">${image ? `<img src="${safe(image)}" alt="" loading="lazy" referrerpolicy="no-referrer" />` : `<span>${safe((item.name || "SQ").slice(0, 3).toUpperCase())}</span>`}</div>
        <div><strong>${safe(item.name)}</strong><small>${safe([item.rarity, item.condition].filter(Boolean).join(" · ") || "No rarity or condition")}${marketHref ? ` · <a class="admin-market-link" href="${safe(marketHref)}" target="_blank" rel="noopener noreferrer">Steam ↗</a>` : ""}</small></div>
        <span class="admin-stock-value"><b>${formatNumber(rewardCost(item))}</b> coins<small class="admin-price-source ${sourceClass}">${safe(sourceLabel)}</small></span>
        <span class="admin-stock-value">${rewardMode(item) === "orderable" ? `<b>Available to order</b><small>ETA ${formatNumber(item.order_eta_days || 8)}+ days</small>` : `<b>${formatNumber(stock.available)}</b> in stock<small>${formatNumber(stock.reserved)} reserved / ${formatNumber(stock.total)} total${item.fulfillment_mode === "orderable" ? " · order fallback" : ""}</small>`}</span>
        ${statusPill(item.active ? "active" : "inactive")}
        <div class="admin-row-actions">${state.owner ? `<button class="admin-row-action" type="button" data-edit-reward="${safe(item.id)}">Edit</button><button class="admin-row-action" type="button" data-toggle-reward="${safe(item.id)}">${item.active ? "Hide" : "Activate"}</button>${item.catalog_managed ? "" : `<button class="admin-row-action is-danger" type="button" data-delete-reward="${safe(item.id)}">Delete</button>`}` : ""}</div>
      </div>`;
    }).join("")}`;

    $$('[data-edit-reward]', target).forEach((button) => button.addEventListener("click", () => openRewardEditor(state.rewards.find((item) => Number(item.id) === Number(button.dataset.editReward)))));
    $$('[data-toggle-reward]', target).forEach((button) => button.addEventListener("click", () => toggleReward(Number(button.dataset.toggleReward))));
    $$('[data-delete-reward]', target).forEach((button) => button.addEventListener("click", () => deleteManualReward(Number(button.dataset.deleteReward))));
  }

  async function loadPricingDashboard() {
    try {
      const data = await rpc("sq_admin_reward_pricing_dashboard");
      state.pricing = data?.settings || null;
      state.catalogSync = data?.sync || null;
      state.rewardStats = data?.stats || null;
      renderPricingDashboard();
      renderRewardStats();
    } catch (error) {
      const progress = $("#steamCatalogProgress");
      if (progress) {
        progress.classList.add("has-error");
        progress.innerHTML = `<span><strong>Pricing database unavailable.</strong> Confirm the existing v14.5 pricing SQL is installed before using Steam sync.</span>`;
      }
      if (!isMissingRpc(error)) throw error;
    }
  }

  function renderPricingDashboard() {
    const settings = state.pricing || {};
    const sync = state.catalogSync || {};
    const stats = state.rewardStats || {};
    if ($("#pricingMarkupPercent")) $("#pricingMarkupPercent").value = settings.markup_percent ?? 15;
    if ($("#pricingCoinsPerEur")) $("#pricingCoinsPerEur").value = settings.coins_per_eur ?? 100;
    if ($("#pricingMaxAgeHours")) $("#pricingMaxAgeHours").value = settings.max_price_age_hours ?? 48;
    if ($("#pricingDefaultEtaDays")) $("#pricingDefaultEtaDays").value = settings.catalog_default_eta_days ?? 8;
    if ($("#pricingMinimumCoins")) $("#pricingMinimumCoins").value = settings.minimum_coin_price ?? 1;
    if ($("#pricingAutoPublish")) $("#pricingAutoPublish").checked = settings.catalog_auto_publish !== false;

    const stale = Number(stats.stale_prices || 0);
    const health = $("#steamPricingHealth");
    if (health) health.innerHTML = `<span class="admin-pricing-health-badge ${stale ? "is-warning" : ""}">${stale ? `${formatNumber(stale)} prices need refresh` : "Prices protected"}</span>`;

    const progress = $("#steamCatalogProgress");
    if (!progress) return;
    const total = Number(sync.total_count || 0);
    const next = Number(sync.next_start || 0);
    const percent = total > 0 ? Math.min(100, Math.round((next / total) * 100)) : 0;
    progress.classList.toggle("has-error", Boolean(sync.last_error));
    if (sync.last_error) {
      progress.innerHTML = `<span><strong>Last Steam sync failed.</strong> ${safe(sync.last_error)} The cursor was kept so the next run can retry safely.</span>`;
    } else if (total > 0) {
      const completed = next === 0 && sync.last_completed_at;
      progress.innerHTML = `<span><strong>${completed ? "Full market pass complete" : `${percent}% of this market pass scanned`}.</strong> ${formatNumber(stats.catalog_items || 0)} eligible CS2 listings stored · last batch ${safe(relativeTime(sync.last_run_at))}${sync.last_completed_at ? ` · last full pass ${safe(relativeTime(sync.last_completed_at))}` : ""}.</span>`;
    } else {
      progress.innerHTML = '<span><strong>No Steam catalog pass yet.</strong> Save the pricing rules, then run the first batch. Scheduled sync can continue from the saved cursor.</span>';
    }
  }

  async function saveRewardPricing(event) {
    event.preventDefault();
    if (!state.owner) return notify("Owner access is required.", "error");
    const markup = Number($("#pricingMarkupPercent")?.value);
    const coinsPerEur = Number($("#pricingCoinsPerEur")?.value);
    const maxAge = Number($("#pricingMaxAgeHours")?.value);
    const eta = Number($("#pricingDefaultEtaDays")?.value);
    const minimum = Number($("#pricingMinimumCoins")?.value);
    if (!Number.isFinite(markup) || markup < 0 || markup > 500) return notify("Markup must be between 0% and 500%.", "error");
    if (!Number.isFinite(coinsPerEur) || coinsPerEur < 0.01 || coinsPerEur > 100000) return notify("Coins per €1 must be between 0.01 and 100,000.", "error");
    if (!Number.isInteger(maxAge) || maxAge < 1 || maxAge > 168) return notify("Price validity must be between 1 and 168 hours.", "error");
    if (!Number.isInteger(eta) || eta < 7 || eta > 30) return notify("Default ETA must be between 7 and 30 days.", "error");
    if (!Number.isInteger(minimum) || minimum < 1 || minimum > 1000000) return notify("Minimum price must be between 1 and 1,000,000 coins.", "error");
    const button = $('button[type="submit"]', event.currentTarget);
    const restore = buttonBusy(button, "Saving…");
    try {
      await rpc("sq_admin_update_reward_pricing_settings", {
        p_markup_percent: markup,
        p_coins_per_eur: coinsPerEur,
        p_minimum_coin_price: minimum,
        p_max_price_age_hours: maxAge,
        p_catalog_auto_publish: Boolean($("#pricingAutoPublish")?.checked),
        p_catalog_default_eta_days: eta
      });
      notify("Steam pricing rules saved and linked coin prices recalculated.", "success");
      await Promise.allSettled([loadPricingDashboard(), loadRewards({ reset: true }), loadAudit()]);
    } catch (error) {
      notify(error.message || "Could not save Steam pricing.", "error");
    } finally {
      restore();
    }
  }

  async function syncSteamCatalog(event) {
    if (!state.owner) return notify("Owner access is required.", "error");
    const button = event?.currentTarget || $("#syncSteamCatalog");
    const restore = buttonBusy(button, "Syncing five pages…");
    try {
      const { data, error } = await sb.functions.invoke("steam-market-sync", { body: { action: "catalog", max_pages: 5 } });
      if (error) throw error;
      if (!data?.ok) throw new Error(data?.error || "Steam sync did not complete.");
      notify(`Steam batch synced: ${formatNumber(data.eligible || 0)} eligible listings from ${formatNumber(data.scanned || 0)} market results.`, "success");
      await Promise.allSettled([loadPricingDashboard(), loadRewards({ reset: true }), loadKpis(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not sync the Steam market. The saved cursor was not lost.", "error");
      await loadPricingDashboard();
    } finally {
      restore();
    }
  }

  function updateRewardEditorMode() {
    const orderable = $("#rewardFulfillmentMode")?.value === "orderable";
    const eta = $("#rewardOrderEtaDays");
    if (eta) eta.disabled = !orderable;
  }

  function updateRewardEditorPricing() {
    const linked = $("#rewardPricingMode")?.value === "steam";
    const cost = $("#rewardCost");
    const marketName = $("#rewardMarketName");
    const help = $("#rewardPriceHelp");
    const status = $("#rewardSteamPriceStatus");
    const item = state.editingReward;
    if (cost) cost.disabled = linked;
    if (marketName) marketName.required = linked;
    if (help) help.textContent = linked ? "Calculated from the latest Steam price and global markup." : "Manual prices are never changed by market sync.";
    if (!status) return;
    status.classList.toggle("is-warning", linked && !steamPriceIsCurrent(item));
    if (!linked) status.textContent = "Manual override enabled. Steam sync can still update item metadata, but not its coin price.";
    else if (Number(item?.steam_price_minor || 0) > 0) status.textContent = `${formatSteamMoney(item)} on Steam · ${formatNumber(rewardCost(item))} coins · updated ${relativeTime(item.steam_price_updated_at)}${steamPriceIsCurrent(item) ? "" : " · refresh required"}`;
    else status.textContent = "No Steam price stored. Import this item with Steam sync before enabling it as a linked listing.";
  }

  function openRewardEditor(item) {
    if (!state.owner) return notify("Owner access is required to edit rewards.", "error");
    state.lastFocus = document.activeElement;
    state.editingReward = item || null;
    if ($("#rewardFormTitle")) $("#rewardFormTitle").textContent = item ? "Edit reward" : "Add custom reward";
    if ($("#rewardId")) $("#rewardId").value = item?.id || "";
    if ($("#rewardName")) $("#rewardName").value = item?.name || "";
    if ($("#rewardMarketName")) $("#rewardMarketName").value = item?.market_name || "";
    if ($("#rewardPricingMode")) $("#rewardPricingMode").value = item?.pricing_mode === "steam" ? "steam" : "manual";
    if ($("#rewardCost")) $("#rewardCost").value = item ? rewardCost(item) : "";
    if ($("#rewardFulfillmentMode")) $("#rewardFulfillmentMode").value = item?.fulfillment_mode === "orderable" ? "orderable" : "stocked";
    if ($("#rewardOrderEtaDays")) $("#rewardOrderEtaDays").value = item?.order_eta_days ?? state.pricing?.catalog_default_eta_days ?? 8;
    if ($("#rewardTotal")) $("#rewardTotal").value = item?.quantity_total ?? 1;
    if ($("#rewardReserved")) $("#rewardReserved").value = item?.quantity_reserved ?? 0;
    if ($("#rewardRarity")) $("#rewardRarity").value = item?.rarity || "";
    if ($("#rewardCondition")) $("#rewardCondition").value = item?.condition || "";
    if ($("#rewardSort")) $("#rewardSort").value = item?.sort_order ?? 0;
    if ($("#rewardMaxPerUser")) $("#rewardMaxPerUser").value = item?.max_per_user ?? "";
    if ($("#rewardImage")) $("#rewardImage").value = item?.image_url || "";
    if ($("#rewardDescription")) $("#rewardDescription").value = item?.description || "";
    if ($("#rewardActive")) $("#rewardActive").checked = item?.active ?? true;
    updateRewardEditorMode();
    updateRewardEditorPricing();
    window.refreshSkinQuestSelects?.();
    const backdrop = $("#rewardEditorBackdrop");
    backdrop?.classList.remove("hidden");
    backdrop?.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
    window.setTimeout(() => $("#rewardName")?.focus(), 30);
  }

  function closeRewardEditor() {
    const backdrop = $("#rewardEditorBackdrop");
    if (!backdrop || backdrop.classList.contains("hidden")) return;
    backdrop.classList.add("hidden");
    backdrop.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    state.editingReward = null;
    state.lastFocus?.focus?.();
  }

  async function saveReward(event) {
    event.preventDefault();
    if (!state.owner) return notify("Owner access is required.", "error");
    const form = event.currentTarget;
    const button = $('button[type="submit"]', form);
    const id = textValue($("#rewardId")?.value);
    const maxPerUser = textValue($("#rewardMaxPerUser")?.value);
    const pricingMode = $("#rewardPricingMode")?.value === "steam" ? "steam" : "manual";
    const fulfillmentMode = $("#rewardFulfillmentMode")?.value === "orderable" ? "orderable" : "stocked";
    const payload = {
      name: textValue($("#rewardName")?.value),
      market_name: textValue($("#rewardMarketName")?.value) || null,
      pricing_mode: pricingMode,
      manual_price_override: pricingMode === "manual",
      points_coins: Number($("#rewardCost")?.value || 0),
      points_cost: Number($("#rewardCost")?.value || 0),
      fulfillment_mode: fulfillmentMode,
      order_eta_days: Number($("#rewardOrderEtaDays")?.value || state.pricing?.catalog_default_eta_days || 8),
      quantity_total: Number($("#rewardTotal")?.value || 0),
      quantity_reserved: Number($("#rewardReserved")?.value || 0),
      rarity: textValue($("#rewardRarity")?.value) || null,
      condition: textValue($("#rewardCondition")?.value) || null,
      sort_order: Number($("#rewardSort")?.value || 0),
      max_per_user: maxPerUser ? Number(maxPerUser) : null,
      image_url: textValue($("#rewardImage")?.value) || null,
      description: textValue($("#rewardDescription")?.value) || null,
      active: Boolean($("#rewardActive")?.checked)
    };
    if (!payload.name) return notify("Reward name is required.", "error");
    if (pricingMode === "steam" && !payload.market_name) return notify("Steam-linked pricing requires the exact Steam market name.", "error");
    if (pricingMode === "steam" && Number(state.editingReward?.steam_price_minor || 0) <= 0) return notify("Run Steam sync and edit the imported listing instead of creating an unpriced Steam item.", "error");
    if (!Number.isInteger(payload.points_coins) || payload.points_coins < 1) return notify("Coin price must be a whole number of at least 1.", "error");
    if (![payload.quantity_total, payload.quantity_reserved, payload.sort_order, payload.order_eta_days].every(Number.isInteger)) return notify("Stock, ETA and sort values must be whole numbers.", "error");
    if (payload.quantity_total < 0 || payload.quantity_reserved < 0 || payload.quantity_reserved > payload.quantity_total) return notify("Reserved stock must be between 0 and total stock.", "error");
    if (payload.order_eta_days < 7 || payload.order_eta_days > 30) return notify("Order ETA must be between 7 and 30 days.", "error");
    if (payload.max_per_user !== null && (!Number.isInteger(payload.max_per_user) || payload.max_per_user < 1)) return notify("The user limit must be a whole number above 0.", "error");

    const restore = buttonBusy(button, "Saving…");
    try {
      if (id) {
        const { error } = await sb.from("reward_items").update(payload).eq("id", id);
        if (error) throw error;
      } else {
        const result = await rpc("sq_owner_create_manual_reward", { p_reward: payload });
        if (result?.existing) {
          closeRewardEditor();
          if ($("#rewardAdminSearch")) $("#rewardAdminSearch").value = result.name || payload.name;
          await loadRewards({ reset: true });
          const existing = state.rewards.find((item) => Number(item.id) === Number(result.id));
          notify("That reward already exists. Edit its prepared quantity instead of creating a duplicate.", "info");
          if (existing) openRewardEditor(existing);
          return;
        }
      }
      notify(id ? "Reward updated." : "Custom reward created.", "success");
      closeRewardEditor();
      await Promise.allSettled([loadRewards({ reset: true }), loadPricingDashboard(), loadKpis(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not save the reward.", "error");
    } finally {
      restore();
    }
  }

  async function toggleReward(id) {
    if (!state.owner) return;
    const item = state.rewards.find((reward) => Number(reward.id) === Number(id));
    if (!item) return;
    const action = item.active ? "hide" : "activate";
    const confirmed = await confirmAction(`${action === "hide" ? "Hide" : "Activate"} ${item.name}?`, { title: `${action === "hide" ? "Hide" : "Activate"} reward`, confirmText: action === "hide" ? "Hide reward" : "Activate", cancelText: "Cancel", danger: false, icon: "SQ" });
    if (!confirmed) return;
    const { error } = await sb.from("reward_items").update({ active: !item.active }).eq("id", id);
    if (error) return notify(error.message, "error");
    notify(`Reward ${item.active ? "hidden" : "activated"}.`, "success");
    await Promise.allSettled([loadRewards({ reset: true }), loadPricingDashboard(), loadKpis(), loadAudit()]);
    renderOverview();
  }

  async function deleteManualReward(id) {
    if (!state.owner) return notify("Owner access is required.", "error");
    const item = state.rewards.find((reward) => Number(reward.id) === Number(id));
    if (!item || item.catalog_managed) return notify("Only manually created rewards can be deleted.", "error");
    const confirmed = await confirmAction(`Permanently delete ${item.name}? Completed order rows will remain as “Deleted item” with their original name and coin amount. Open orders must be finished or cancelled first.`, { title: "Delete manual reward?", confirmText: "Delete reward", cancelText: "Cancel", danger: true, icon: "!" });
    if (!confirmed) return;
    try {
      await rpc("sq_owner_delete_manual_reward", { p_reward_id: id });
      notify("Manual reward deleted.", "success");
      await Promise.allSettled([loadRewards({ reset: true }), loadPricingDashboard(), loadKpis(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not delete the reward.", "error");
    }
  }

  async function loadSystemStatus() {
    const target = $("#adminSystemStatus");
    if (!target) return;
    const { data, error } = await sb.from("sq_system_status").select("component,display_name,status,message,sort_order,updated_by,updated_at").order("sort_order", { ascending: true });
    if (error) {
      target.innerHTML = `<div class="admin-empty"><strong>System status unavailable</strong>${safe(error.message)}</div>`;
      throw error;
    }
    state.statuses = data || [];
    await hydrateProfiles(state.statuses.map((item) => item.updated_by));
    renderSystemStatus();
    renderOverviewHealth();
  }

  function renderSystemStatus() {
    const target = $("#adminSystemStatus");
    if (!target) return;
    if (!state.statuses.length) {
      target.innerHTML = '<div class="admin-empty">No system components are configured.</div>';
      return;
    }
    target.innerHTML = state.statuses.map((item) => `<div class="admin-status-row" data-system-component="${safe(item.component)}">
      <div class="admin-status-name"><i></i><div><strong>${safe(item.display_name)}</strong><small>Updated ${safe(relativeTime(item.updated_at))}${item.updated_by ? ` by ${safe(adminLabel(item.updated_by))}` : ""}</small></div></div>
      <label>Status<select data-system-status>${["operational", "degraded", "maintenance", "incident"].map((status) => `<option value="${status}" ${status === item.status ? "selected" : ""}>${safe(statusLabel(status))}</option>`).join("")}</select></label>
      <label>Public message<input data-system-message maxlength="240" value="${safe(item.message || "")}" placeholder="What customers should know" /></label>
      <button class="admin-secondary-button" type="button" data-save-system-status>Save</button>
    </div>`).join("");
    $$('[data-save-system-status]', target).forEach((button) => button.addEventListener("click", () => saveSystemStatus(button)));
  }

  async function saveSystemStatus(button) {
    const row = button.closest("[data-system-component]");
    const component = row?.dataset.systemComponent;
    const status = $("[data-system-status]", row)?.value;
    const message = textValue($("[data-system-message]", row)?.value);
    const restore = buttonBusy(button, "Saving…");
    try {
      await rpc("sq_admin_set_system_status", { p_component: component, p_status: status, p_message: message || null });
      notify("System status updated.", "success");
      await Promise.allSettled([loadSystemStatus(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not update system status.", "error");
    } finally { restore(); }
  }

  async function loadPromos() {
    const target = $("#adminPromoList");
    if (!target) return;
    const requestId = ++state.promoRequestId;
    try {
      const result = await rpc("sq_admin_search_promo_codes", {
        p_query: textValue($("#adminPromoSearch")?.value) || null,
        p_state: $("#adminPromoState")?.value || "all",
        p_limit: 200,
        p_offset: 0
      });
      if (requestId !== state.promoRequestId) return;
      state.promos = Array.isArray(result?.items) ? result.items : [];
      state.promoTotal = Number(result?.total ?? state.promos.length);
    } catch (error) {
      if (requestId !== state.promoRequestId) return;
      target.innerHTML = `<div class="admin-empty"><strong>Promo codes unavailable</strong>${safe(error.message)}</div>`;
      throw error;
    }
    await hydrateProfiles(state.promos.map((item) => item.created_by));
    renderPromos();
  }

  function promoState(item) {
    const now = Date.now();
    if (!item.active) return "inactive";
    if (item.starts_at && new Date(item.starts_at).getTime() > now) return "scheduled";
    if (item.ends_at && new Date(item.ends_at).getTime() < now) return "expired";
    if (item.max_redemptions && Number(item.redemptions_count || 0) >= Number(item.max_redemptions)) return "used";
    return "active";
  }

  function renderPromos() {
    const target = $("#adminPromoList");
    if (!target) return;
    if ($("#adminPromoResultCount")) $("#adminPromoResultCount").textContent = state.promoTotal
      ? `Showing ${formatNumber(state.promos.length)} of ${formatNumber(state.promoTotal)}`
      : "No matching codes";
    if (!state.promos.length) {
      target.innerHTML = '<div class="admin-empty"><strong>No promo codes found</strong>Try another code, campaign, or status.</div>';
      return;
    }
    target.innerHTML = state.promos.map((item) => {
      const current = promoState(item);
      return `<div class="admin-promo-row"><div><strong class="admin-case-number">${safe(item.code)}</strong><small>${safe(item.campaign || "No campaign label")}</small></div><div><strong>${formatNumber(item.coin_amount)} coins</strong><small>Created by ${safe(adminLabel(item.created_by))}</small></div><div><strong>${formatNumber(item.redemptions_count)}</strong><small>${item.max_redemptions ? `of ${formatNumber(item.max_redemptions)} uses` : "unlimited"}</small></div><div><strong>${safe(formatShortDate(item.created_at))}</strong><small>${item.ends_at ? `Ends ${safe(formatShortDate(item.ends_at))}` : "No end date"}</small></div><div>${statusPill(current === "scheduled" || current === "used" || current === "expired" ? "inactive" : current)}</div><div class="admin-row-actions"><button class="admin-row-action" type="button" data-copy-promo="${safe(item.code)}">Copy</button>${state.owner ? `<button class="admin-row-action" type="button" data-toggle-promo="${safe(item.id)}">${item.active ? "Disable" : "Enable"}</button><button class="admin-row-action is-danger" type="button" data-delete-promo="${safe(item.id)}">Delete</button>` : ""}</div></div>`;
    }).join("");
    $$('[data-copy-promo]', target).forEach((button) => button.addEventListener("click", () => copyToClipboard(button.dataset.copyPromo, "Promo code copied.")));
    $$('[data-toggle-promo]', target).forEach((button) => button.addEventListener("click", () => togglePromo(Number(button.dataset.togglePromo))));
    $$('[data-delete-promo]', target).forEach((button) => button.addEventListener("click", () => deletePromo(Number(button.dataset.deletePromo))));
  }

  async function togglePromo(id) {
    if (!state.owner) return notify("Owner access is required.", "error");
    const item = state.promos.find((promo) => Number(promo.id) === Number(id));
    if (!item) return;
    try {
      await rpc("sq_owner_set_promo_active", { p_promo_id: id, p_active: !item.active });
      notify(`${item.code} ${item.active ? "disabled" : "enabled"}.`, "success");
      await Promise.allSettled([loadPromos(), loadAudit()]);
    } catch (error) {
      notify(error.message || "Could not update the promo code.", "error");
    }
  }

  async function deletePromo(id) {
    if (!state.owner) return notify("Owner access is required.", "error");
    const item = state.promos.find((promo) => Number(promo.id) === Number(id));
    if (!item) return;
    const used = Number(item.redemptions_count || 0);
    const confirmed = await confirmAction(`Permanently delete promo code ${item.code}? ${used ? `${formatNumber(used)} existing redemption${used === 1 ? "" : "s"} and awarded coins remain in history.` : "The code has no redemptions."}`, { title: "Delete promo code?", confirmText: "Delete code", cancelText: "Cancel", danger: true, icon: "!" });
    if (!confirmed) return;
    try {
      const result = await rpc("sq_owner_delete_promo_code", { p_promo_id: id });
      notify(`Promo code ${item.code} deleted. ${formatNumber(result?.preserved_redemptions || 0)} redemption records preserved.`, "success");
      await Promise.allSettled([loadPromos(), loadAudit()]);
    } catch (error) {
      notify(error.message || "Could not delete the promo code.", "error");
    }
  }

  async function createPromo(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const button = $('button[type="submit"]', form);
    const data = new FormData(form);
    const starts = textValue(data.get("starts"));
    const ends = textValue(data.get("ends"));
    if (starts && ends && new Date(ends) <= new Date(starts)) return notify("Promo end time must be after its start time.", "error");
    const restore = buttonBusy(button, "Creating…");
    try {
      const result = await rpc("sq_admin_create_promo_code", {
        p_code: data.get("code"),
        p_coin_amount: Number(data.get("coins")),
        p_campaign: textValue(data.get("campaign")) || null,
        p_max_redemptions: textValue(data.get("max")) ? Number(data.get("max")) : null,
        p_starts_at: starts ? new Date(starts).toISOString() : null,
        p_ends_at: ends ? new Date(ends).toISOString() : null
      });
      notify(`Promo code ${result.code} created.`, "success");
      form.reset();
      form.elements.coins.value = 50;
      await Promise.allSettled([loadPromos(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not create the promo code.", "error");
    } finally { restore(); }
  }

  async function loadAudit() {
    const target = $("#adminAuditList");
    if (!target) return;
    const { data, error } = await sb.from("sq_admin_audit_log").select("id,actor_user_id,action,entity_type,entity_id,details,created_at").order("created_at", { ascending: false }).limit(250);
    if (error) {
      target.innerHTML = `<div class="admin-empty"><strong>Audit trail unavailable</strong>${safe(error.message)}</div>`;
      throw error;
    }
    state.audit = data || [];
    await hydrateProfiles(state.audit.map((item) => item.actor_user_id));
    renderAudit();
    renderOverviewAudit();
  }

  function auditActionLabel(action) {
    const labels = {
      redemption_status_update: "Order status updated",
      support_status_update: "Support ticket updated",
      system_status_update: "System status updated",
      promo_create: "Promo code created",
      promo_status_update: "Promo code status changed",
      promo_delete: "Promo code deleted",
      reward_delete: "Manual reward deleted",
      admin_role_update: "Admin access changed",
      coin_adjustment: "Coin balance adjusted",
      reward_pricing_settings_update: "Steam pricing updated",
      insert: "Reward created",
      update: "Reward updated",
      delete: "Reward deleted"
    };
    return labels[action] || statusLabel(action);
  }

  function auditEntityLabel(row) {
    const details = row.details || {};
    return details.order_number || details.ticket_number || details.code || details.name || `${textValue(row.entity_type).replaceAll("_", " ")} ${row.entity_id || ""}`.trim();
  }

  function auditDetail(row) {
    const details = row.details || {};
    if (row.action === "delete" && row.entity_type === "reward_item") return "Catalog entry removed; order history preserved";
    if (details.from_status || details.to_status) return `${statusLabel(details.from_status)} → ${statusLabel(details.to_status)}`;
    if (row.action === "coin_adjustment") return `${Number(details.amount || 0) > 0 ? "+" : ""}${formatNumber(details.amount)} coins · ${details.reason || "Manual adjustment"}`;
    if (row.action === "admin_role_update") return `${details.previous_role || "No access"} → ${details.role || "No access"}`;
    if (row.action === "system_status_update") return statusLabel(details.status);
    if (row.action === "promo_create") return `${formatNumber(details.coins)} coins${details.max ? ` · ${formatNumber(details.max)} uses` : ""}`;
    if (row.action === "promo_status_update") return details.active ? "Enabled" : "Disabled";
    if (row.action === "promo_delete") return `${formatNumber(details.redemptions || 0)} redemption record${Number(details.redemptions || 0) === 1 ? "" : "s"} preserved`;
    if (row.action === "reward_delete") return "Catalog entry removed; order history preserved";
    if (row.action === "reward_pricing_settings_update") return `${details.markup_percent ?? "?"}% markup · ${details.coins_per_eur ?? "?"} coins/€`;
    if (row.entity_type === "reward_item") return details.active_before === details.active_after ? "Inventory details changed" : `${details.active_before ? "Visible" : "Hidden"} → ${details.active_after ? "Visible" : "Hidden"}`;
    return "Change recorded";
  }

  function auditIcon(action) {
    if (action.includes("redemption")) return "RO";
    if (action.includes("support")) return "SP";
    if (action.includes("coin")) return "$";
    if (action.includes("role")) return "AD";
    if (action.includes("promo")) return "PC";
    if (action.includes("status")) return "ST";
    return "RW";
  }

  function renderAudit() {
    const target = $("#adminAuditList");
    if (!target) return;
    const search = textValue($("#adminAuditSearch")?.value).toLowerCase();
    const rows = state.audit.filter((row) => [row.action, row.entity_type, row.entity_id, auditEntityLabel(row), auditDetail(row), adminLabel(row.actor_user_id)].some((value) => String(value || "").toLowerCase().includes(search)));
    if (!rows.length) {
      target.innerHTML = '<div class="admin-empty"><strong>No audit events found</strong>Try another audit search.</div>';
      return;
    }
    target.innerHTML = rows.map((row) => `<div class="admin-audit-row"><span class="admin-audit-icon">${safe(auditIcon(row.action))}</span><div><strong>${safe(auditActionLabel(row.action))}</strong><small>${safe(auditEntityLabel(row))}</small></div><div><strong>${safe(adminLabel(row.actor_user_id))}</strong><small>${safe(auditDetail(row))}</small></div><time class="admin-audit-time" datetime="${safe(row.created_at)}">${safe(formatDateTime(row.created_at))}</time></div>`).join("");
  }

  function renderTeam() {
    const target = $("#adminUsersList");
    if (!target) return;
    if (!state.admins.length) {
      target.innerHTML = '<div class="admin-empty">No admin accounts were returned.</div>';
      return;
    }
    target.innerHTML = state.admins.map((item) => `<div class="admin-team-row"><span class="admin-account-avatar">${safe((adminLabel(item.user_id)[0] || "A").toUpperCase())}</span><div><strong>${safe(adminLabel(item.user_id))}</strong><small>${item.user_id === state.user?.id ? "Current account" : "SkinQuest admin"}</small></div><div><strong>${safe(shortId(item.user_id))}</strong><small>${safe(item.user_id)}</small></div>${statusPill(item.role === "owner" ? "active" : "open")}<span class="admin-case-date">Added ${safe(formatShortDate(item.created_at))}</span></div>`).join("");
  }

  async function saveAdminRole(event) {
    event.preventDefault();
    if (!state.owner) return notify("Owner access is required.", "error");
    const form = event.currentTarget;
    const button = $('button[type="submit"]', form);
    const identifier = textValue($("#roleUserIdentifier")?.value);
    const role = $("#roleValue")?.value;
    if (!identifier) return notify("Enter a user email or user ID.", "error");
    const confirmed = await confirmAction(role === "remove" ? `Remove admin access from ${identifier}?` : `Set ${identifier} as ${role}?`, { title: "Update team access", confirmText: role === "remove" ? "Remove access" : "Save access", cancelText: "Cancel", danger: role === "remove", icon: role === "owner" ? "★" : "AD" });
    if (!confirmed) return;
    const restore = buttonBusy(button, "Saving…");
    try {
      await rpc("owner_set_admin_role", { p_user_identifier: identifier, p_role: role });
      notify("Admin access updated.", "success");
      form.reset();
      await Promise.allSettled([loadAdminDirectory(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not update admin access.", "error");
    } finally { restore(); }
  }

  async function applyCoinAdjustment(event) {
    event.preventDefault();
    if (!state.owner) return notify("Owner access is required.", "error");
    const form = event.currentTarget;
    const button = $('button[type="submit"]', form);
    const identifier = textValue($("#coinUserIdentifier")?.value);
    const amount = Number($("#coinAmount")?.value || 0);
    const reason = textValue($("#coinReason")?.value);
    if (!identifier) return notify("Enter a user email or user ID.", "error");
    if (!Number.isInteger(amount) || amount === 0) return notify("Amount must be a whole number other than 0.", "error");
    if (reason.length < 3) return notify("Add a clear reason for the audit trail.", "error");
    const confirmed = await confirmAction(`Apply ${amount > 0 ? "+" : ""}${formatNumber(amount)} coins to ${identifier}?`, { title: "Adjust coin balance", confirmText: "Apply adjustment", cancelText: "Cancel", danger: amount < 0, icon: "$" });
    if (!confirmed) return;
    const restore = buttonBusy(button, "Applying…");
    try {
      const result = await rpc("admin_adjust_user_coins", { p_user_identifier: identifier, p_amount: amount, p_reason: reason });
      notify(`Balance updated to ${formatNumber(result.balance)} coins.`, "success");
      form.reset();
      await Promise.allSettled([loadCoinHistory(), loadKpis(), loadAudit()]);
      renderOverview();
    } catch (error) {
      notify(error.message || "Could not adjust the balance.", "error");
    } finally { restore(); }
  }

  async function loadCoinHistory() {
    const target = $("#adminCoinHistory");
    if (!target || !state.owner) return;
    const { data, error } = await sb.from("coin_adjustments").select("id,user_id,amount,reason,created_by,created_at").eq("source_type", "admin_adjustment").order("created_at", { ascending: false }).limit(75);
    if (error) {
      target.innerHTML = `<div class="admin-empty"><strong>Adjustment history unavailable</strong>${safe(error.message)}</div>`;
      throw error;
    }
    state.coinHistory = data || [];
    await hydrateProfiles(state.coinHistory.flatMap((item) => [item.user_id, item.created_by]));
    target.innerHTML = state.coinHistory.length ? state.coinHistory.map((item) => `<div class="admin-audit-row"><span class="admin-audit-icon">$</span><div><strong>${item.amount > 0 ? "+" : ""}${formatNumber(item.amount)} coins</strong><small>${safe(item.reason || "Manual adjustment")}</small></div><div><strong>${safe(profileLabel(item.user_id))}</strong><small>By ${safe(adminLabel(item.created_by))}</small></div><time class="admin-audit-time">${safe(formatDateTime(item.created_at))}</time></div>`).join("") : '<div class="admin-empty">No manual coin adjustments yet.</div>';
  }

  window.initAdminV145 = initAdminV145;
})();
