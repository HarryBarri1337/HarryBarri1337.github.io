/* SkinQuest v14.1.2 product upgrade layer.
   Loaded after app.js. The full setup includes the v14 database layer;
   v14.1.2 itself requires no schema changes.
   This layer extends the secure SkinQuest core without replacing reward authority.
*/

(() => {
  "use strict";

  const VERSION = "14.1.2";
  const GA_ID = "G-DFRR03C4BP";
  const ATTRIBUTION_KEY = "skinquest.firstTouch.v14";
  const CONSENT_KEY = "skinquest.cookieConsent.v1";
  const VISIT_KEY = "skinquest.visitCount.v1";
  const LAST_PROMO_KEY = "skinquest.pendingPromo.v1";
  const LAST_REF_KEY = "skinquest.pendingReferral.v1";
  const MAX_TEXT = 500;

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const routeSegment = (location.pathname.split("/").filter(Boolean).pop() || "").toLowerCase();
  const path = !routeSegment
    ? "index.html"
    : routeSegment === "surveys"
      ? "earn.html"
      : routeSegment.endsWith(".html")
        ? routeSegment
        : `${routeSegment}.html`;
  const IS_CAMPAIGN_PAGE = /^\/0?[1-5](?:\/|$)/.test(location.pathname);

  function client() {
    try {
      return typeof sb !== "undefined" ? sb : null;
    } catch {
      return null;
    }
  }

  function safeText(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function clampText(value, length = MAX_TEXT) {
    return String(value ?? "").slice(0, length);
  }

  function formatNumber(value) {
    return Number(value || 0).toLocaleString();
  }

  function formatDate(value) {
    if (!value) return "";
    try {
      return new Intl.DateTimeFormat(undefined, {
        year: "numeric",
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit"
      }).format(new Date(value));
    } catch {
      return String(value);
    }
  }

  function notify(message, type = "success") {
    try {
      if (typeof showMessage === "function") {
        showMessage(message, type);
        return;
      }
    } catch {}

    let shell = $("#sqV14ToastShell");
    if (!shell) {
      shell = document.createElement("div");
      shell.id = "sqV14ToastShell";
      shell.className = "sq-v14-toast-shell";
      document.body.appendChild(shell);
    }
    const toast = document.createElement("div");
    toast.className = `sq-v14-toast sq-v14-toast-${type}`;
    toast.textContent = message;
    shell.appendChild(toast);
    setTimeout(() => toast.classList.add("show"), 10);
    setTimeout(() => {
      toast.classList.remove("show");
      setTimeout(() => toast.remove(), 180);
    }, 3200);
  }

  async function currentUser() {
    const c = client();
    if (!c) return null;
    try {
      const { data } = await c.auth.getUser();
      return data?.user || null;
    } catch {
      return null;
    }
  }

  async function rpc(name, args = undefined) {
    const c = client();
    if (!c) throw new Error("Supabase is not available on this page.");
    const result = await c.rpc(name, args);
    if (result.error) throw result.error;
    return result.data;
  }

  async function copy(value, success = "Copied.") {
    try {
      await navigator.clipboard.writeText(value);
      notify(success);
    } catch {
      const temp = document.createElement("textarea");
      temp.value = value;
      temp.style.position = "fixed";
      temp.style.opacity = "0";
      document.body.appendChild(temp);
      temp.select();
      document.execCommand("copy");
      temp.remove();
      notify(success);
    }
  }

  function create(tag, className, html = "") {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (html) el.innerHTML = html;
    return el;
  }

  function isStandalone() {
    return window.matchMedia?.("(display-mode: standalone)")?.matches || window.navigator.standalone === true;
  }

  // ---------------------------------------------------------------------------
  // Consent-controlled analytics
  // ---------------------------------------------------------------------------
  function getConsent() {
    try {
      return JSON.parse(localStorage.getItem(CONSENT_KEY) || "null");
    } catch {
      return null;
    }
  }

  function setConsent(analytics) {
    const value = { analytics: !!analytics, updatedAt: new Date().toISOString() };
    localStorage.setItem(CONSENT_KEY, JSON.stringify(value));
    if (value.analytics) loadAnalytics();
    $("#sqCookieBanner")?.remove();
    return value;
  }

  function loadAnalytics() {
    if (!getConsent()?.analytics || window.__skinquestGaLoaded) return;
    window.__skinquestGaLoaded = true;
    window.dataLayer = window.dataLayer || [];
    window.gtag = window.gtag || function gtag() { window.dataLayer.push(arguments); };
    window.gtag("js", new Date());
    window.gtag("config", GA_ID, { anonymize_ip: true });

    const script = document.createElement("script");
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(GA_ID)}`;
    document.head.appendChild(script);
  }

  function showConsentManager(force = false) {
    if (!force && getConsent()) {
      loadAnalytics();
      return;
    }
    if ($("#sqCookieBanner")) return;

    const banner = create("section", "sq-cookie-banner", `
      <div>
        <strong>Cookie preferences</strong>
        <p>SkinQuest uses essential storage for account/site features. Analytics is optional and only loads if you allow it.</p>
      </div>
      <div class="sq-cookie-actions">
        <button class="button button-ghost" type="button" data-sq-consent="reject">Essential only</button>
        <button class="button button-primary" type="button" data-sq-consent="accept">Allow analytics</button>
      </div>
    `);
    banner.id = "sqCookieBanner";
    document.body.appendChild(banner);
    banner.querySelector('[data-sq-consent="reject"]')?.addEventListener("click", () => setConsent(false));
    banner.querySelector('[data-sq-consent="accept"]')?.addEventListener("click", () => setConsent(true));
  }

  function addCookiePreferencesLink() {
    const links = $(".footer-links");
    if (!links || $("[data-sq-cookie-settings]", links)) return;
    const a = document.createElement("a");
    a.href = "#cookie-preferences";
    a.dataset.sqCookieSettings = "true";
    a.textContent = "Cookie preferences";
    a.addEventListener("click", (event) => {
      event.preventDefault();
      showConsentManager(true);
    });
    links.appendChild(a);
  }

  function gaEvent(name, params = {}) {
    if (!getConsent()?.analytics) return;
    loadAnalytics();
    try { window.gtag?.("event", name, params); } catch {}
  }

  // ---------------------------------------------------------------------------
  // Attribution + campaign tracking
  // ---------------------------------------------------------------------------
  function captureAttribution() {
    let existing = null;
    try { existing = JSON.parse(localStorage.getItem(ATTRIBUTION_KEY) || "null"); } catch {}
    const params = new URLSearchParams(location.search);

    const referral = params.get("ref") || params.get("referral");
    const promo = params.get("code") || params.get("promo");
    if (referral) localStorage.setItem(LAST_REF_KEY, referral.slice(0, 64));
    if (promo) localStorage.setItem(LAST_PROMO_KEY, promo.slice(0, 64));

    if (existing) return existing;

    const value = {
      source: params.get("utm_source") || null,
      medium: params.get("utm_medium") || null,
      campaign: params.get("utm_campaign") || null,
      content: params.get("utm_content") || null,
      term: params.get("utm_term") || null,
      landing_path: clampText(location.pathname + location.search, 500),
      referrer: clampText(document.referrer, 500) || null,
      referral_code: referral?.slice(0, 64) || null,
      promo_code: promo?.slice(0, 64) || null,
      captured_at: new Date().toISOString()
    };
    try { localStorage.setItem(ATTRIBUTION_KEY, JSON.stringify(value)); } catch {}
    return value;
  }

  async function persistAttribution(user) {
    if (!user) return;
    let a;
    try { a = JSON.parse(localStorage.getItem(ATTRIBUTION_KEY) || "null"); } catch {}
    if (!a) return;
    try {
      await rpc("sq_set_acquisition", {
        p_source: a.source,
        p_medium: a.medium,
        p_campaign: a.campaign,
        p_content: a.content,
        p_term: a.term,
        p_landing_path: a.landing_path,
        p_referrer: a.referrer,
        p_referral_code: a.referral_code,
        p_promo_code: a.promo_code
      });
    } catch {}
  }

  async function applyPendingReferral(user) {
    if (!user) return;
    const code = localStorage.getItem(LAST_REF_KEY);
    if (!code) return;
    try {
      await rpc("sq_claim_referral_code", { p_code: code });
      localStorage.removeItem(LAST_REF_KEY);
    } catch (error) {
      const message = String(error?.message || "").toLowerCase();
      if (message.includes("yourself") || message.includes("not found")) localStorage.removeItem(LAST_REF_KEY);
    }
  }

  async function trackProduct(eventName, properties = {}) {
    const user = await currentUser();
    if (!user) return false;
    try {
      await rpc("sq_track_event", {
        p_event_name: eventName,
        p_page_path: location.pathname,
        p_properties: properties
      });
      return true;
    } catch {
      return false;
    }
  }

  function bindFunnelTracking() {
    document.addEventListener("click", (event) => {
      const reward = event.target.closest?.("[data-redeem]");
      if (reward) {
        trackProduct("redeem_click", { reward_id: Number(reward.dataset.redeem || 0) || null });
        gaEvent("redeem_click", { reward_id: reward.dataset.redeem || "" });
      }

      const provider = event.target.closest?.(".provider-action, #openCpxWall, #openBitLabsWall, [data-provider]");
      if (provider) {
        const label = provider.dataset.provider || provider.id || provider.textContent?.trim().slice(0, 80) || "provider";
        trackProduct("provider_open", { provider: label });
        gaEvent("provider_open", { provider: label });
      }

      const favorite = event.target.closest?.("[data-favorite-star]");
      if (favorite) {
        trackProduct("reward_goal_click", { reward_id: Number(favorite.dataset.favoriteStar || 0) || null });
      }
    }, { passive: true });
  }

  // ---------------------------------------------------------------------------
  // Activity / streak
  // ---------------------------------------------------------------------------
  async function recordActivity(user) {
    if (!user) return null;
    try {
      const data = await rpc("sq_record_activity");
      return data;
    } catch {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Offline indicator
  // ---------------------------------------------------------------------------
  function initOfflineIndicator() {
    const bar = create("div", "sq-offline-bar", "Offline — account balances and reward stock may be outdated.");
    bar.id = "sqOfflineBar";
    document.body.prepend(bar);

    const sync = () => bar.classList.toggle("show", !navigator.onLine);
    window.addEventListener("online", sync);
    window.addEventListener("offline", sync);
    sync();
  }

  // ---------------------------------------------------------------------------
  // Mobile navigation
  // ---------------------------------------------------------------------------
  function initMobileNav() {
    if ($("#sqMobileNav")) return;
    const nav = create("nav", "sq-mobile-nav", `
      <a href="/" data-page="index.html" aria-label="Home"><span>⌂</span><small>Home</small></a>
      <a href="/surveys" data-page="earn.html" aria-label="Surveys"><span>✓</span><small>Surveys</small></a>
      <a href="/rewards" data-page="rewards.html" aria-label="Rewards"><span>◇</span><small>Rewards</small></a>
      <a href="/dashboard" data-page="dashboard.html" aria-label="Dashboard"><span>◎</span><small>Dashboard</small></a>
    `);
    nav.id = "sqMobileNav";
    nav.querySelector(`[data-page="${path}"]`)?.classList.add("active");
    document.body.appendChild(nav);
  }

  // ---------------------------------------------------------------------------
  // Notification center
  // ---------------------------------------------------------------------------
  let notificationButton = null;
  let notificationDrawer = null;

  function ensureNotificationUi() {
    // The notification button is rendered INSIDE #navAuthActions by app.js.
    // Never insert another direct child into .site-header: that breaks its
    // three-column desktop grid and pushes auth controls onto another row.
    notificationButton = $("#sqNotificationButton");

    if (!notificationDrawer) {
      notificationDrawer = $("#sqNotificationDrawer");
    }

    if (!notificationDrawer) {
      notificationDrawer = create("aside", "sq-notification-drawer", `
        <div class="sq-drawer-head">
          <div><span class="pill">Activity</span><h2>Notifications</h2></div>
          <div class="sq-drawer-head-actions">
            <button type="button" class="sq-mark-all-read hidden" data-sq-mark-all-read>Mark all read</button>
            <button type="button" class="sq-icon-button" data-sq-close-notifications aria-label="Close notifications">×</button>
          </div>
        </div>
        <div class="sq-notification-list" data-sq-notification-list><div class="empty-state">Loading…</div></div>
      `);
      notificationDrawer.id = "sqNotificationDrawer";
      notificationDrawer.setAttribute("aria-hidden", "true");
      document.body.appendChild(notificationDrawer);

      notificationDrawer.querySelector("[data-sq-close-notifications]")?.addEventListener("click", () => toggleNotificationDrawer(false));
      notificationDrawer.querySelector("[data-sq-mark-all-read]")?.addEventListener("click", async (event) => {
        const button = event.currentTarget;
        const previousText = button.textContent;
        button.disabled = true;
        button.textContent = "Marking…";
        try {
          await rpc("sq_mark_all_notifications_read");
          await Promise.all([loadNotifications(), refreshNotificationCount()]);
        } catch (error) {
          notify(error.message || "Could not update notifications.", "error");
        } finally {
          button.disabled = false;
          button.textContent = previousText;
        }
      });
    }

    // app.js re-renders #navAuthActions when auth/profile data changes, so use
    // delegated events instead of attaching a click handler to a disposable node.
    if (!window.__skinquestV14NotificationDelegation) {
      window.__skinquestV14NotificationDelegation = true;
      document.addEventListener("click", (event) => {
        const button = event.target.closest("#sqNotificationButton");
        if (!button) return;
        notificationButton = button;
        toggleNotificationDrawer();
      });
      document.addEventListener("keydown", (event) => {
        if (event.key === "Escape") toggleNotificationDrawer(false);
      });

      const actions = $("#navAuthActions");
      if (actions && "MutationObserver" in window) {
        const observer = new MutationObserver(() => {
          const button = $("#sqNotificationButton");
          if (!button) return;
          notificationButton = button;
          refreshNotificationCount();
        });
        observer.observe(actions, { childList: true, subtree: true });
      }
    }
  }

  async function refreshNotificationCount() {
    const user = await currentUser();
    const badge = $("[data-sq-notification-count]");
    if (!badge) return;
    if (!user) {
      badge.classList.add("hidden");
      return;
    }

    const c = client();
    try {
      const { count, error } = await c
        .from("sq_notifications")
        .select("id", { count: "exact", head: true })
        .is("read_at", null);
      if (error) throw error;
      const n = Number(count || 0);
      badge.textContent = n > 99 ? "99+" : String(n);
      badge.classList.toggle("hidden", n === 0);
    } catch {
      badge.classList.add("hidden");
    }
  }

  function toggleNotificationDrawer(open = null) {
    if (!notificationDrawer || !notificationButton) return;
    const willOpen = open ?? !notificationDrawer.classList.contains("open");
    notificationDrawer.classList.toggle("open", willOpen);
    notificationDrawer.setAttribute("aria-hidden", String(!willOpen));
    notificationButton.setAttribute("aria-expanded", String(willOpen));
    if (willOpen) loadNotifications();
  }

  async function loadNotifications() {
    const list = $("[data-sq-notification-list]");
    const markAllButton = $("[data-sq-mark-all-read]", notificationDrawer || document);
    if (!list) return;
    const user = await currentUser();
    if (!user) {
      markAllButton?.classList.add("hidden");
      list.innerHTML = `<div class="empty-state">Sign in to see notifications.</div>`;
      return;
    }

    const c = client();
    const { data, error } = await c
      .from("sq_notifications")
      .select("id, notification_type, title, body, href, metadata, read_at, created_at")
      .order("created_at", { ascending: false })
      .limit(30);

    if (error) {
      markAllButton?.classList.add("hidden");
      list.innerHTML = `<div class="empty-state">Notifications are unavailable right now.</div>`;
      return;
    }
    if (!data?.length) {
      markAllButton?.classList.add("hidden");
      list.innerHTML = `<div class="empty-state">Nothing new yet.</div>`;
      return;
    }

    markAllButton?.classList.toggle("hidden", !data.some((item) => !item.read_at));
    list.innerHTML = data.map((item) => {
      const requestId = String(item.metadata?.request_id ?? "").trim();
      const rewardTarget = /^\d+$/.test(requestId)
        ? `/dashboard?request=${encodeURIComponent(requestId)}#redeem-request-${encodeURIComponent(requestId)}`
        : "/dashboard#redeem-requests";
      const href = item.notification_type === "reward" ? rewardTarget : (item.href || "");
      return `
        <button class="sq-notification-row ${item.read_at ? "" : "unread"}" type="button" data-sq-notification-id="${item.id}" data-href="${safeText(href)}">
          <span class="sq-notification-dot"></span>
          <span>
            <strong>${safeText(item.title)}</strong>
            ${item.body ? `<small>${safeText(item.body)}</small>` : ""}
            <time>${safeText(formatDate(item.created_at))}</time>
          </span>
        </button>`;
    }).join("");

    $$('[data-sq-notification-id]', list).forEach((row) => {
      row.addEventListener("click", async () => {
        const id = Number(row.dataset.sqNotificationId);
        try { await rpc("sq_mark_notification_read", { p_notification_id: id }); } catch {}
        row.classList.remove("unread");
        markAllButton?.classList.toggle("hidden", !list.querySelector(".sq-notification-row.unread"));
        refreshNotificationCount();
        const href = row.dataset.href;
        if (href) {
          toggleNotificationDrawer(false);
          location.href = href;
        }
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Homepage: keep the landing page focused and visually clean.
  // v14.0.3 deliberately avoids injecting dashboard-style stats or status cards
  // below the hero. Those features live on the dashboard/admin pages instead.
  // ---------------------------------------------------------------------------
  async function enhanceHomepage() {
    if (path !== "index.html" || IS_CAMPAIGN_PAGE) return;

    const hero = $(".hero-copy");
    if (!hero) return;

    const h1 = $("h1", hero);
    const p = $("p", hero);
    const pill = $(".pill", hero);

    if (pill) pill.textContent = "Fixed CS2 rewards";
    if (h1) h1.textContent = "Earn coins. Redeem real CS2 rewards.";
    if (p) p.textContent = "Complete verified partner tasks, collect SkinQuest coins, and choose the exact CS2 reward you want. No deposits, no cases, no roulette.";
  }

  // ---------------------------------------------------------------------------
  // Dashboard: achievements, streak, referrals, promo codes
  // ---------------------------------------------------------------------------
  function injectDashboardShell() {
    if (path !== "dashboard.html") return;
    const account = $("#accountSection");
    if (!account || $("#sqGrowthHub")) return;

    const hub = create("section", "sq-growth-hub", `
      <section class="panel sq-next-action-panel" data-sq-next-action>
        <div><span class="pill">Next move</span><h2>Keep your next reward moving</h2><p class="muted">Complete another verified task and move closer to your next reward.</p></div>
        <a class="button button-primary" href="/surveys">Continue earning</a>
      </section>

      <section class="sq-growth-stats sq-growth-stats-compact" data-sq-growth-stats>
        <article class="stat-card"><span>Current streak</span><strong>—</strong><p>Consecutive active days.</p></article>
        <article class="stat-card"><span>Longest streak</span><strong>—</strong><p>Your personal best.</p></article>
        <article class="stat-card"><span>Achievements</span><strong>—</strong><p>Permanent milestones unlocked.</p></article>
      </section>

      <section class="panel sq-achievement-panel">
        <div class="sq-section-head compact"><div><span class="pill">Profile</span><h2>Achievements</h2><p class="muted">Permanent milestones unlocked from real account activity.</p></div></div>
        <div class="sq-achievement-grid sq-achievement-grid-compact" data-sq-achievements><div class="empty-state">Loading achievements…</div></div>
      </section>

      <section class="sq-promo-ref-grid">
        <article class="panel">
          <div class="sq-section-head compact"><div><span class="pill">Bonus cards</span><h2>Redeem a code</h2></div></div>
          <form class="sq-inline-form" data-sq-promo-form>
            <input type="text" maxlength="64" placeholder="SQ-XXXXX" autocomplete="off" data-sq-promo-input required />
            <button class="button button-primary" type="submit">Redeem</button>
          </form>
          <p class="muted compact-copy sq-promo-help">One-use promotional codes can come from SkinQuest campaigns, QR cards, or creator promotions.</p>
        </article>
        <article class="panel">
          <div class="sq-section-head compact"><div><span class="pill">Invite</span><h2>Your referral link</h2></div></div>
          <div class="sq-referral-box" data-sq-referral-box><div class="empty-state compact-empty">Loading referral code…</div></div>
        </article>
      </section>
    `);
    hub.id = "sqGrowthHub";
    account.appendChild(hub);

    const pendingPromo = localStorage.getItem(LAST_PROMO_KEY);
    if (pendingPromo) {
      const input = $("[data-sq-promo-input]", hub);
      if (input) input.value = pendingPromo;
    }

    hub.querySelector("[data-sq-promo-form]")?.addEventListener("submit", redeemPromoFromForm);
  }

  async function loadGrowthHub() {
    if (path !== "dashboard.html") return;
    injectDashboardShell();
    const user = await currentUser();
    if (!user) return;

    try { await rpc("sq_refresh_my_progress"); } catch {}

    try {
      const summary = await rpc("sq_get_my_growth_summary");
      const cards = $$('[data-sq-growth-stats] .stat-card');
      const values = [
        `${formatNumber(summary?.current_streak)}d`,
        `${formatNumber(summary?.longest_streak)}d`,
        formatNumber(summary?.achievements)
      ];
      cards.forEach((card, i) => {
        const strong = $("strong", card);
        if (strong) strong.textContent = values[i] ?? "—";
      });
    } catch {}

    const c = client();
    try {
      const [{ data: achievements }, { data: unlocked }] = await Promise.all([
        c.from("sq_achievements").select("achievement_key,title,description,icon,sort_order").eq("active", true).order("sort_order"),
        c.from("sq_user_achievements").select("achievement_key,unlocked_at")
      ]);
      renderAchievements(achievements || [], unlocked || []);
    } catch {}

    loadReferralBox();
  }


  function renderAchievements(items, unlockedRows) {
    const target = $("[data-sq-achievements]");
    if (!target) return;
    const unlocked = new Map(unlockedRows.map((a) => [a.achievement_key, a]));
    target.innerHTML = items.map((item) => {
      const row = unlocked.get(item.achievement_key);
      return `
        <article class="sq-achievement ${row ? "unlocked" : "locked"}">
          <span class="sq-achievement-icon">${safeText(item.icon || "★")}</span>
          <div><strong>${safeText(item.title)}</strong><p>${safeText(item.description)}</p>${row ? `<small>Unlocked ${safeText(formatDate(row.unlocked_at))}</small>` : `<small>Locked</small>`}</div>
        </article>`;
    }).join("");
  }

  async function redeemPromoFromForm(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const input = $("[data-sq-promo-input]", form);
    const button = $('button[type="submit"]', form);
    const code = input?.value.trim();
    if (!code) return;
    button.disabled = true;
    const old = button.textContent;
    button.textContent = "Checking…";
    try {
      const data = await rpc("sq_redeem_promo_code", { p_code: code });
      localStorage.removeItem(LAST_PROMO_KEY);
      notify(`Code redeemed: +${formatNumber(data?.coins_awarded)} coins.`);
      input.value = "";
      trackProduct("promo_success", { coins: Number(data?.coins_awarded || 0) });
      setTimeout(() => location.reload(), 800);
    } catch (error) {
      notify(error.message || "Could not redeem that code.", "error");
    } finally {
      button.disabled = false;
      button.textContent = old;
    }
  }

  async function loadReferralBox() {
    const target = $("[data-sq-referral-box]");
    if (!target) return;
    try {
      const code = await rpc("sq_get_or_create_referral_code");
      const link = `${location.origin}/?ref=${encodeURIComponent(code)}`;
      const c = client();
      const { data } = await c.from("sq_referrals").select("referred_user_id,qualified_at,reward_issued_at");
      const total = data?.length || 0;
      const qualified = (data || []).filter((r) => r.qualified_at).length;
      target.innerHTML = `
        <div class="sq-referral-link"><code>${safeText(link)}</code><button class="mini-button" type="button" data-sq-copy-ref>Copy</button></div>
        <div class="sq-referral-stats"><span><strong>${formatNumber(total)}</strong> referrals</span><span><strong>${formatNumber(qualified)}</strong> qualified</span></div>
        <p class="muted compact-copy">Referral rewards are only issued after a referral qualifies; creating accounts alone does not pay a bonus.</p>`;
      target.querySelector("[data-sq-copy-ref]")?.addEventListener("click", () => copy(link, "Referral link copied."));
    } catch (error) {
      target.innerHTML = `<div class="empty-state compact-empty">Referral link unavailable.</div>`;
    }
  }

  // ---------------------------------------------------------------------------
  // Rewards: extra filters, progress-to-price, details, restock alerts
  // ---------------------------------------------------------------------------
  const rewardFilters = { weapon: "all", condition: "all", rarity: "all" };
  let rewardObserver = null;

  const rewardFilterOptions = {
    weapon: [
      ["all", "All weapons"], ["ak-47", "AK-47"], ["m4a1-s", "M4A1-S"], ["m4a4", "M4A4"],
      ["awp", "AWP"], ["usp-s", "USP-S"], ["glock-18", "Glock-18"],
      ["desert eagle", "Desert Eagle"], ["p250", "P250"], ["case", "Case"]
    ],
    condition: [
      ["all", "All conditions"], ["fn", "Factory New"], ["mw", "Minimal Wear"],
      ["ft", "Field-Tested"], ["ww", "Well-Worn"], ["bs", "Battle-Scarred"]
    ],
    rarity: [
      ["all", "All rarities"], ["consumer", "Consumer"], ["industrial", "Industrial"],
      ["mil-spec", "Mil-Spec"], ["restricted", "Restricted"], ["classified", "Classified"],
      ["covert", "Covert"]
    ]
  };

  function rewardFilterDropdown(label, key) {
    const options = rewardFilterOptions[key] || [];
    const labelId = `sq${key[0].toUpperCase()}${key.slice(1)}FilterLabel`;
    const valueId = `sq${key[0].toUpperCase()}${key.slice(1)}FilterValue`;
    return `
      <div class="sq-extra-filter-group">
        <span class="sq-extra-filter-label" id="${labelId}">${label}</span>
        <div class="custom-select sq-extra-custom-select" data-sq-filter-dropdown="${key}">
          <button class="custom-select-trigger sq-extra-select-trigger" type="button" aria-haspopup="listbox" aria-expanded="false" aria-labelledby="${labelId} ${valueId}">
            <span id="${valueId}" data-sq-selected-label>${options[0]?.[1] || label}</span>
            <span class="select-chevron" aria-hidden="true">⌄</span>
          </button>
          <div class="custom-select-menu sq-extra-select-menu" role="listbox" aria-labelledby="${labelId}" aria-hidden="true">
            ${options.map(([value, optionLabel], index) => `<button class="custom-select-option${index === 0 ? " active" : ""}" type="button" role="option" tabindex="-1" aria-selected="${index === 0}" data-sq-filter-option="${value}">${optionLabel}</button>`).join("")}
          </div>
        </div>
      </div>`;
  }

  function injectRewardExtraFilters() {
    if (path !== "rewards.html") return;
    const status = $(".reward-shop-status");
    if (!status || $("#sqRewardExtraFilters")) return;
    const bar = create("section", "sq-extra-reward-filters", `
      ${rewardFilterDropdown("Weapon", "weapon")}
      ${rewardFilterDropdown("Condition", "condition")}
      ${rewardFilterDropdown("Rarity", "rarity")}
      <button class="sq-extra-filter-reset" type="button" data-sq-clear-extra disabled>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4.9 7.5A8 8 0 1 1 4 14"/><path d="M4.9 3.5v4h4"/></svg>
        <span>Reset filters</span>
      </button>
    `);
    bar.id = "sqRewardExtraFilters";
    bar.setAttribute("aria-label", "More reward filters");
    status.parentNode.insertBefore(bar, status);

    const dropdowns = $$('[data-sq-filter-dropdown]', bar);
    const resetButton = $("[data-sq-clear-extra]", bar);

    const closeDropdown = (dropdown, returnFocus = false) => {
      if (!dropdown) return;
      dropdown.classList.remove("open");
      const trigger = $(".sq-extra-select-trigger", dropdown);
      $(".sq-extra-select-menu", dropdown)?.setAttribute("aria-hidden", "true");
      trigger?.setAttribute("aria-expanded", "false");
      if (returnFocus) trigger?.focus();
    };

    const closeAllDropdowns = (except = null) => {
      dropdowns.forEach((dropdown) => {
        if (dropdown !== except) closeDropdown(dropdown);
      });
    };

    const updateResetButton = () => {
      const active = Object.values(rewardFilters).some((value) => value !== "all");
      if (!resetButton) return;
      resetButton.disabled = !active;
      resetButton.classList.toggle("is-active", active);
    };

    const chooseOption = (dropdown, option) => {
      const key = dropdown?.dataset.sqFilterDropdown;
      if (!key || !option) return;
      const value = option.dataset.sqFilterOption || "all";
      rewardFilters[key] = value.toLowerCase();
      $("[data-sq-selected-label]", dropdown).textContent = option.textContent.trim();
      $$('[data-sq-filter-option]', dropdown).forEach((candidate) => {
        const selected = candidate === option;
        candidate.classList.toggle("active", selected);
        candidate.setAttribute("aria-selected", String(selected));
      });
      closeDropdown(dropdown, true);
      updateResetButton();
      applyRewardEnhancements();
    };

    dropdowns.forEach((dropdown) => {
      const trigger = $(".sq-extra-select-trigger", dropdown);
      const menu = $(".sq-extra-select-menu", dropdown);
      const options = $$('[data-sq-filter-option]', dropdown);

      const openDropdown = (focusOption = false, fromEnd = false) => {
        closeAllDropdowns(dropdown);
        dropdown.classList.add("open");
        menu?.setAttribute("aria-hidden", "false");
        trigger?.setAttribute("aria-expanded", "true");
        if (focusOption) {
          const activeOption = options.find((option) => option.classList.contains("active"));
          (fromEnd ? options[options.length - 1] : activeOption || options[0])?.focus();
        }
      };

      trigger?.addEventListener("click", (event) => {
        event.preventDefault();
        if (dropdown.classList.contains("open")) closeDropdown(dropdown);
        else openDropdown();
      });

      trigger?.addEventListener("keydown", (event) => {
        if (!["ArrowDown", "ArrowUp", "Enter", " "].includes(event.key)) return;
        event.preventDefault();
        openDropdown(true, event.key === "ArrowUp");
      });

      options.forEach((option) => option.addEventListener("click", () => chooseOption(dropdown, option)));

      menu?.addEventListener("keydown", (event) => {
        const currentIndex = options.indexOf(document.activeElement);
        let nextIndex = currentIndex;
        if (event.key === "ArrowDown") nextIndex = Math.min(options.length - 1, currentIndex + 1);
        else if (event.key === "ArrowUp") nextIndex = Math.max(0, currentIndex - 1);
        else if (event.key === "Home") nextIndex = 0;
        else if (event.key === "End") nextIndex = options.length - 1;
        else if (event.key === "Escape") {
          event.preventDefault();
          closeDropdown(dropdown, true);
          return;
        } else return;
        event.preventDefault();
        options[nextIndex]?.focus();
      });
    });

    document.addEventListener("click", (event) => {
      if (!bar.contains(event.target)) closeAllDropdowns();
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") closeAllDropdowns();
    });
    bar.addEventListener("focusout", () => {
      window.setTimeout(() => {
        if (!bar.contains(document.activeElement)) closeAllDropdowns();
      }, 0);
    });

    resetButton?.addEventListener("click", () => {
      rewardFilters.weapon = rewardFilters.condition = rewardFilters.rarity = "all";
      dropdowns.forEach((dropdown) => {
        const firstOption = $("[data-sq-filter-option]", dropdown);
        if (!firstOption) return;
        $("[data-sq-selected-label]", dropdown).textContent = firstOption.textContent.trim();
        $$('[data-sq-filter-option]', dropdown).forEach((option, index) => {
          option.classList.toggle("active", index === 0);
          option.setAttribute("aria-selected", String(index === 0));
        });
        closeDropdown(dropdown);
      });
      updateResetButton();
      applyRewardEnhancements();
    });
  }

  function conditionMatches(text, filter) {
    if (filter === "all") return true;
    const aliases = {
      fn: ["factory new", " fn"],
      mw: ["minimal wear", " mw"],
      ft: ["field-tested", "field tested", " ft"],
      ww: ["well-worn", "well worn", " ww"],
      bs: ["battle-scarred", "battle scarred", " bs"]
    };
    return (aliases[filter] || [filter]).some((x) => text.includes(x));
  }

  async function getBalance() {
    const user = await currentUser();
    if (!user) return 0;
    const c = client();
    try {
      const { data } = await c.from("profiles").select("points_balance").eq("id", user.id).maybeSingle();
      return Number(data?.points_balance || 0);
    } catch {
      return 0;
    }
  }

  function parseCardCost(card) {
    const priceText = $(".price", card)?.textContent || "";
    const n = Number(priceText.replace(/[^0-9]/g, ""));
    return Number.isFinite(n) ? n : 0;
  }

  async function applyRewardEnhancements() {
    if (path !== "rewards.html") return;
    const grid = $("#rewardsGrid");
    if (!grid) return;
    const balance = await getBalance();
    const cards = $$(".reward-card", grid);

    for (const card of cards) {
      const text = ` ${card.textContent?.toLowerCase() || ""}`;
      const title = $("h2", card)?.textContent?.toLowerCase() || "";
      const weaponMatch = rewardFilters.weapon === "all" || title.includes(rewardFilters.weapon.toLowerCase());
      const conditionMatch = conditionMatches(text, rewardFilters.condition);
      const rarityMatch = rewardFilters.rarity === "all" || text.includes(rewardFilters.rarity);
      const star = $("[data-favorite-star]", card);
      card.classList.toggle("sq-extra-hidden", !(weaponMatch && conditionMatch && rarityMatch));

      if (!$(".sq-reward-progress", card)) {
        const cost = parseCardCost(card);
        if (cost > 0) {
          const remaining = Math.max(0, cost - balance);
          const pct = Math.min(100, (balance / cost) * 100);
          const progress = create("div", "sq-reward-progress", `
            <div class="sq-reward-progress-copy"><span>${balance > 0 ? `${formatNumber(balance)} / ${formatNumber(cost)} coins` : `${formatNumber(cost)} coins`}</span><strong>${remaining === 0 ? "Ready to redeem" : `${formatNumber(remaining)} remaining`}</strong></div>
            <div class="sq-mini-progress"><span style="width:${pct}%"></span></div>
          `);
          const actions = $(".reward-actions", card);
          actions?.parentNode.insertBefore(progress, actions);
        }
      }

      const redeem = $("[data-redeem]", card);
      const rewardId = Number(redeem?.dataset.redeem || star?.dataset.favoriteStar || 0);
      if (rewardId && card.classList.contains("is-out") && !$("[data-sq-stock-alert]", card)) {
        const btn = create("button", "mini-button sq-stock-alert", "Notify when available");
        btn.type = "button";
        btn.dataset.sqStockAlert = String(rewardId);
        $(".reward-actions", card)?.appendChild(btn);
        btn.addEventListener("click", async (event) => {
          event.preventDefault();
          event.stopPropagation();
          if (!await currentUser()) {
            try { if (typeof openAuthModal === "function") openAuthModal("signup"); } catch {}
            return;
          }
          btn.disabled = true;
          try {
            const result = await rpc("sq_toggle_stock_alert", { p_reward_id: rewardId });
            btn.textContent = result?.subscribed ? "Alert enabled ✓" : "Notify when available";
            btn.classList.toggle("active", !!result?.subscribed);
            notify(result?.subscribed ? "We’ll add an in-app notification when this reward is restocked." : "Stock alert removed.");
          } catch (error) {
            notify(error.message || "Could not update stock alert.", "error");
          } finally {
            btn.disabled = false;
          }
        });
      }

      if (!card.dataset.sqDetailBound) {
        card.dataset.sqDetailBound = "true";
        const art = $(".reward-art, .reward-image, h2", card);
        art?.addEventListener("click", (event) => {
          if (event.target.closest("button,a")) return;
          openRewardDetail(card);
        });
      }
    }

    const visible = cards.filter((card) => !card.classList.contains("sq-extra-hidden")).length;
    const count = $("#rewardResultCount");
    const extraActive = rewardFilters.weapon !== "all" || rewardFilters.condition !== "all" || rewardFilters.rarity !== "all";
    if (count) {
      if (!count.textContent.includes("with extra filters")) count.dataset.sqBaseText = count.textContent;
      count.textContent = extraActive
        ? `Showing ${formatNumber(visible)} rewards with extra filters`
        : count.dataset.sqBaseText || `Showing ${formatNumber(visible)} rewards`;
    }
  }

  function openRewardDetail(card) {
    $("#sqRewardDetail")?.remove();
    const title = $("h2", card)?.textContent?.trim() || "CS2 reward";
    const description = $(".reward-description", card)?.textContent?.trim() || "Fixed SkinQuest reward delivered through a reviewed Steam trade.";
    const price = $(".price", card)?.textContent?.trim() || "";
    const stock = $$(".stock-pill", card).map((x) => x.textContent.trim()).join(" · ");
    const image = $(".reward-art img, img", card)?.src || "";
    const rewardId = Number($("[data-redeem]", card)?.dataset.redeem || $("[data-favorite-star]", card)?.dataset.favoriteStar || 0);

    const modal = create("div", "sq-modal-backdrop", `
      <article class="sq-reward-detail" role="dialog" aria-modal="true" aria-labelledby="sqRewardDetailTitle">
        <button type="button" class="sq-icon-button sq-detail-close" aria-label="Close">×</button>
        <div class="sq-detail-art">${image ? `<img src="${safeText(image)}" alt="" />` : `<strong>CS2</strong>`}</div>
        <div class="sq-detail-copy">
          <span class="pill">Fixed reward</span>
          <h2 id="sqRewardDetailTitle">${safeText(title)}</h2>
          <p>${safeText(description)}</p>
          <div class="sq-detail-meta"><strong>${safeText(price)}</strong><span>${safeText(stock || "Stock shown in the reward store")}</span></div>
          <div class="sq-detail-safety"><strong>How delivery works</strong><span>Redeem at a fixed coin price. SkinQuest reviews the request and sends approved rewards using the Steam trade URL saved to your account.</span></div>
          <div class="hero-actions"><button class="button button-primary" type="button" data-sq-detail-redeem>Use reward action</button><button class="button button-ghost" type="button" data-sq-detail-close>Close</button></div>
        </div>
      </article>`);
    modal.id = "sqRewardDetail";
    document.body.appendChild(modal);
    modal.querySelectorAll("[data-sq-detail-close], .sq-detail-close").forEach((btn) => btn.addEventListener("click", () => modal.remove()));
    modal.addEventListener("click", (event) => { if (event.target === modal) modal.remove(); });
    modal.querySelector("[data-sq-detail-redeem]")?.addEventListener("click", () => {
      modal.remove();
      const original = card.querySelector(`[data-redeem="${rewardId}"]`) || card.querySelector("[data-reward-action]");
      original?.click();
    });
    setTimeout(() => modal.classList.add("open"), 10);
  }

  function watchRewardGrid() {
    const grid = $("#rewardsGrid");
    if (!grid || rewardObserver) return;
    let timer;
    rewardObserver = new MutationObserver(() => {
      clearTimeout(timer);
      timer = setTimeout(applyRewardEnhancements, 35);
    });
    rewardObserver.observe(grid, { childList: true, subtree: true });
    applyRewardEnhancements();

    const params = new URLSearchParams(location.search);
    const rewardId = Number(params.get("reward") || 0);
    if (rewardId) {
      const attempt = () => {
        const card = $(`[data-redeem="${rewardId}"]`)?.closest(".reward-card");
        if (card) {
          card.scrollIntoView({ behavior: "smooth", block: "center" });
          card.classList.add("sq-highlight-reward");
          setTimeout(() => card.classList.remove("sq-highlight-reward"), 2400);
        }
      };
      setTimeout(attempt, 700);
    }
  }

  // ---------------------------------------------------------------------------
  // Hide user-facing development leakage
  // ---------------------------------------------------------------------------
  function hideDevelopmentLeakage() {
    const phrases = ["credentials required", "before launch", "future integration", "provider approval first", "not connected yet"];
    $$(".provider-card, .settings-card, .readiness-item").forEach((card) => {
      const text = card.textContent?.toLowerCase() || "";
      if (phrases.some((phrase) => text.includes(phrase))) card.classList.add("sq-development-hidden");
    });
  }

  // ---------------------------------------------------------------------------
  // Admin: real KPIs, promo creator, status editor, audit log
  // ---------------------------------------------------------------------------
  const ADMIN_COLLAPSE_STORAGE_KEY = "skinquest.adminCollapsed.v1";

  function initAdminCollapsibles(root) {
    if (!root) return;
    let collapsedSections = new Set();
    try {
      const saved = JSON.parse(localStorage.getItem(ADMIN_COLLAPSE_STORAGE_KEY) || "[]");
      if (Array.isArray(saved)) collapsedSections = new Set(saved.map(String));
    } catch {}

    const saveCollapsedSections = () => {
      try { localStorage.setItem(ADMIN_COLLAPSE_STORAGE_KEY, JSON.stringify([...collapsedSections])); } catch {}
    };

    $$(".panel", root).forEach((section, index) => {
      if (section.dataset.sqAdminCollapsible === "true") return;
      const header = section.querySelector(":scope > .section-headline, :scope > .sq-section-head");
      const title = header?.querySelector("h2");
      if (!header || !title) return;

      const titleSlug = (title.textContent || `section-${index + 1}`)
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-|-$/g, "") || `section-${index + 1}`;
      const sectionKey = `${titleSlug}-${index + 1}`;
      const bodyId = `sqAdminSectionBody${index + 1}`;

      section.dataset.sqAdminCollapsible = "true";
      section.dataset.sqAdminSection = sectionKey;
      section.classList.add("sq-admin-collapsible");
      header.classList.add("sq-admin-collapse-head");

      const titleBlock = [...header.children].find((child) => child.contains(title)) || header.firstElementChild;
      const actions = create("div", "sq-admin-collapse-actions");
      [...header.children].filter((child) => child !== titleBlock).forEach((child) => actions.appendChild(child));
      header.appendChild(actions);

      const toggle = create("button", "sq-admin-collapse-toggle", `
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 10l4 4 4-4"/></svg>
      `);
      toggle.type = "button";
      toggle.setAttribute("aria-controls", bodyId);
      actions.appendChild(toggle);

      const body = create("div", "sq-admin-collapse-body");
      body.id = bodyId;
      [...section.children].filter((child) => child !== header).forEach((child) => body.appendChild(child));
      section.appendChild(body);

      const setCollapsed = (collapsed) => {
        section.classList.toggle("is-collapsed", collapsed);
        body.hidden = collapsed;
        toggle.setAttribute("aria-expanded", String(!collapsed));
        toggle.setAttribute("aria-label", `${collapsed ? "Expand" : "Collapse"} ${title.textContent.trim()}`);
        if (collapsed) collapsedSections.add(sectionKey);
        else collapsedSections.delete(sectionKey);
      };

      setCollapsed(collapsedSections.has(sectionKey));
      toggle.addEventListener("click", () => {
        setCollapsed(!section.classList.contains("is-collapsed"));
        saveCollapsedSections();
      });
    });
  }

  async function enhanceAdmin() {
    if (path !== "admin.html") return;
    const panel = $("#adminPanel");
    if (!panel || $("#sqAdminV14")) return;

    const shell = create("section", "sq-admin-v14", `
      <section class="panel sq-admin-overview-panel">
        <div class="sq-section-head"><div><span class="pill">v${VERSION}</span><h2>Operating overview</h2></div><button class="mini-button" type="button" data-sq-refresh-admin>Refresh</button></div>
        <div class="sq-admin-kpis" data-sq-admin-kpis><div class="empty-state">Loading KPIs…</div></div>
      </section>
      <section class="sq-admin-two-col">
        <article class="panel sq-admin-promo-panel">
          <div class="sq-section-head compact"><div><span class="pill">Campaigns</span><h2>Create promo code</h2></div></div>
          <form class="sq-admin-promo-form" data-sq-admin-promo-form>
            <label>Code<input name="code" maxlength="64" placeholder="SQ-UPPSALA-01" required /></label>
            <label>Coins<input name="coins" type="number" min="1" max="100000" value="50" required /></label>
            <label>Campaign<input name="campaign" maxlength="160" placeholder="Printed cards August" /></label>
            <label>Maximum uses<input name="max" type="number" min="1" placeholder="50" /></label>
            <button class="button button-primary" type="submit">Create code</button>
          </form>
        </article>
        <article class="panel sq-admin-health-panel">
          <div class="sq-section-head compact"><div><span class="pill">Health</span><h2>Public system status</h2></div></div>
          <div class="sq-admin-status-list" data-sq-admin-status><div class="empty-state">Loading status…</div></div>
        </article>
      </section>
      <section class="panel sq-admin-audit-panel">
        <div class="sq-section-head compact"><div><span class="pill">Security</span><h2>Recent admin audit</h2></div></div>
        <div class="sq-audit-list" data-sq-audit-list><div class="empty-state">Loading audit log…</div></div>
      </section>
    `);
    shell.id = "sqAdminV14";
    panel.prepend(shell);

    initAdminCollapsibles(panel);
    shell.querySelector("[data-sq-refresh-admin]")?.addEventListener("click", () => loadAdminV14Data());
    shell.querySelector("[data-sq-admin-promo-form]")?.addEventListener("submit", createAdminPromo);
    await loadAdminV14Data();
  }

  async function loadAdminV14Data() {
    const kpiTarget = $("[data-sq-admin-kpis]");
    try {
      const kpi = await rpc("sq_admin_kpis");
      if (kpiTarget) kpiTarget.innerHTML = [
        ["Users", kpi.users, `${formatNumber(kpi.new_users_24h)} new / 24h`],
        ["Coin liability", kpi.coin_liability, "coins held by users"],
        ["Open rewards", kpi.open_rewards, `${formatNumber(kpi.completed_rewards)} completed total`],
        ["Support", kpi.open_support, "new / open tickets"],
        ["Active rewards", kpi.active_rewards, "listed now"],
        ["Positive credits", kpi.positive_coin_credits_24h, "coins / 24h"]
      ].map(([label, value, detail]) => `
        <article class="sq-admin-kpi-card">
          <span>${safeText(label)}</span>
          <strong>${formatNumber(value)}</strong>
          <small>${safeText(detail)}</small>
        </article>`).join("");
    } catch (error) {
      if (kpiTarget) kpiTarget.innerHTML = `<div class="empty-state">Admin KPIs unavailable.</div>`;
    }

    const c = client();
    const statusTarget = $("[data-sq-admin-status]");
    try {
      const { data } = await c.from("sq_system_status").select("component,display_name,status,message,updated_at").order("sort_order");
      if (statusTarget) {
        statusTarget.innerHTML = (data || []).map((item) => `
          <div class="sq-admin-status-row" data-component="${safeText(item.component)}" data-current-status="${safeText(item.status)}">
            <div class="sq-admin-status-copy"><strong>${safeText(item.display_name)}</strong><span>${safeText(item.message || "No public message set")}</span></div>
            <select data-sq-status-select aria-label="Status for ${safeText(item.display_name)}">
              ${["operational","degraded","maintenance","incident"].map((status) => `<option value="${status}" ${item.status === status ? "selected" : ""}>${status[0].toUpperCase()}${status.slice(1)}</option>`).join("")}
            </select>
            <button class="mini-button sq-admin-status-save" type="button" data-sq-save-status>Save</button>
          </div>`).join("");
        $$('[data-sq-save-status]', statusTarget).forEach((button) => button.addEventListener("click", saveSystemStatus));
      }
    } catch {
      if (statusTarget) statusTarget.innerHTML = `<div class="empty-state">Status controls unavailable.</div>`;
    }

    const auditTarget = $("[data-sq-audit-list]");
    try {
      const { data } = await c.from("sq_admin_audit_log").select("id,actor_user_id,action,entity_type,entity_id,details,created_at").order("created_at", { ascending: false }).limit(30);
      if (auditTarget) auditTarget.innerHTML = data?.length ? data.map((row) => `
        <div class="sq-audit-row"><span><strong>${safeText(row.action)}</strong><small>${safeText(row.entity_type)} · ${safeText(row.entity_id || "")}</small></span><code>${safeText(JSON.stringify(row.details || {}))}</code><time>${safeText(formatDate(row.created_at))}</time></div>
      `).join("") : `<div class="empty-state">No audit events yet.</div>`;
    } catch {
      if (auditTarget) auditTarget.innerHTML = `<div class="empty-state">Audit log unavailable.</div>`;
    }
  }

  async function createAdminPromo(event) {
    event.preventDefault();
    const form = event.currentTarget;
    const button = $('button[type="submit"]', form);
    const fd = new FormData(form);
    button.disabled = true;
    try {
      const result = await rpc("sq_admin_create_promo_code", {
        p_code: fd.get("code"),
        p_coin_amount: Number(fd.get("coins")),
        p_campaign: String(fd.get("campaign") || "") || null,
        p_max_redemptions: fd.get("max") ? Number(fd.get("max")) : null,
        p_starts_at: null,
        p_ends_at: null
      });
      notify(`Promo code ${result.code} created.`);
      form.reset();
      form.elements.coins.value = 50;
      loadAdminV14Data();
    } catch (error) {
      notify(error.message || "Could not create promo code.", "error");
    } finally {
      button.disabled = false;
    }
  }

  async function saveSystemStatus(event) {
    const row = event.currentTarget.closest("[data-component]");
    const component = row?.dataset.component;
    const status = $("[data-sq-status-select]", row)?.value;
    if (!component || !status) return;
    const c = client();
    try {
      const { error } = await c.rpc("sq_admin_set_system_status", {
        p_component: component,
        p_status: status,
        p_message: null
      });
      if (error) throw error;
      notify("System status updated.");
      loadAdminV14Data();
    } catch (error) {
      notify(error.message || "Could not update status.", "error");
    }
  }

  // ---------------------------------------------------------------------------
  // Install prompt after repeat visit (not first-page harassment)
  // ---------------------------------------------------------------------------
  let deferredInstallPrompt = null;

  function initInstallPrompt() {
    if (isStandalone()) return;
    let visits = Number(localStorage.getItem(VISIT_KEY) || 0) + 1;
    localStorage.setItem(VISIT_KEY, String(Math.min(visits, 999)));

    window.addEventListener("beforeinstallprompt", (event) => {
      event.preventDefault();
      deferredInstallPrompt = event;
      if (visits >= 2) showInstallNudge();
    });
  }

  function showInstallNudge() {
    if ($("#sqInstallNudge") || isStandalone()) return;
    const nudge = create("aside", "sq-install-nudge", `
      <div><strong>Add SkinQuest to your device</strong><span>Faster access to Surveys, Rewards and your Dashboard.</span></div>
      <div><button class="button button-primary" type="button" data-sq-install-now>Install</button><button class="sq-icon-button" type="button" data-sq-dismiss-install aria-label="Dismiss">×</button></div>
    `);
    nudge.id = "sqInstallNudge";
    document.body.appendChild(nudge);
    nudge.querySelector("[data-sq-dismiss-install]")?.addEventListener("click", () => nudge.remove());
    nudge.querySelector("[data-sq-install-now]")?.addEventListener("click", async () => {
      if (deferredInstallPrompt) {
        deferredInstallPrompt.prompt();
        const choice = await deferredInstallPrompt.userChoice;
        gaEvent("pwa_install_prompt", { outcome: choice?.outcome || "unknown" });
        deferredInstallPrompt = null;
        nudge.remove();
      } else {
        location.href = "/install";
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Small accessibility and product polish
  // ---------------------------------------------------------------------------
  function improveAccessibility() {
    $$('button:not([type])').forEach((button) => button.setAttribute("type", "button"));
    $$('img:not([alt])').forEach((img) => img.setAttribute("alt", ""));

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") $("#sqRewardDetail")?.remove();
    });
  }

  // ---------------------------------------------------------------------------
  // Auth-aware refresh loop
  // ---------------------------------------------------------------------------
  async function afterAuthReady() {
    const user = await currentUser();
    if (!IS_CAMPAIGN_PAGE) ensureNotificationUi();
    if (user) {
      await Promise.allSettled([
        persistAttribution(user),
        applyPendingReferral(user),
        recordActivity(user)
      ]);
      refreshNotificationCount();
      if (path === "dashboard.html") loadGrowthHub();
    } else {
      refreshNotificationCount();
    }
  }

  function bindAuthWatcher() {
    const c = client();
    if (!c) return;
    try {
      c.auth.onAuthStateChange((_event, session) => {
        if (session?.user) {
          setTimeout(() => afterAuthReady(), 120);
        } else {
          setTimeout(() => refreshNotificationCount(), 120);
        }
      });
    } catch {}
  }

  async function bootV14() {
    captureAttribution();
    addCookiePreferencesLink();
    showConsentManager(false);
    initOfflineIndicator();
    improveAccessibility();
    bindFunnelTracking();
    hideDevelopmentLeakage();
    bindAuthWatcher();

    if (!IS_CAMPAIGN_PAGE) {
      initMobileNav();
      initInstallPrompt();
      injectRewardExtraFilters();
      watchRewardGrid();
      injectDashboardShell();
    }

    await Promise.allSettled([
      enhanceHomepage(),
      IS_CAMPAIGN_PAGE ? Promise.resolve() : enhanceAdmin(),
      afterAuthReady()
    ]);

    window.addEventListener("focus", () => refreshNotificationCount());
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) refreshNotificationCount();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => setTimeout(bootV14, 80), { once: true });
  } else {
    setTimeout(bootV14, 80);
  }
})();
