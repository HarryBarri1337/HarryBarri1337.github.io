// SkinQuest v2 frontend.
// No fake coin rewards are included.
// Real balances must be handled by a backend and credited only through verified offerwall postbacks.

const OFFERWALL_URL = "https://example.com/offerwall?user_id=";
// Replace with your real offerwall URL after publisher approval.
// Example pattern from most providers: provider_offerwall_url + your internal user ID.

const rewards = [
  { id: "p250-sand", name: "P250 | Sand Dune", tier: "Starter", price: 120, art: "P250" },
  { id: "glock-moonrise", name: "Glock-18 | Moonrise", tier: "Budget", price: 260, art: "G18" },
  { id: "usp-ticket", name: "USP-S | Ticket to Hell", tier: "Budget", price: 350, art: "USP" },
  { id: "ak-slate", name: "AK-47 | Slate", tier: "Popular", price: 900, art: "AK" },
  { id: "m4-night", name: "M4A1-S | Night Terror", tier: "Popular", price: 1100, art: "M4" },
  { id: "awp-atheris", name: "AWP | Atheris", tier: "Premium", price: 1500, art: "AWP" }
];

const store = {
  get(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(key)) ?? fallback;
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    localStorage.setItem(key, JSON.stringify(value));
  }
};

function initNav() {
  const toggle = document.querySelector("[data-nav-toggle]");
  const nav = document.querySelector("[data-nav]");
  if (!toggle || !nav) return;

  toggle.addEventListener("click", () => {
    nav.classList.toggle("open");
  });

  const current = location.pathname.split("/").pop() || "index.html";
  nav.querySelectorAll("a").forEach((link) => {
    if (link.getAttribute("href") === current) link.classList.add("active");
  });
}

function initOfferwall() {
  const button = document.getElementById("openOfferwall");
  if (!button) return;

  button.addEventListener("click", () => {
    const userId = store.get("skinquest_user_id", null) || crypto.randomUUID();
    store.set("skinquest_user_id", userId);

    if (OFFERWALL_URL.includes("example.com")) {
      alert("Add your real offerwall URL in app.js first.");
      return;
    }

    window.open(OFFERWALL_URL + encodeURIComponent(userId), "_blank");
  });
}

function renderRewards() {
  const grid = document.getElementById("rewardsGrid");
  if (!grid) return;

  const search = document.getElementById("skinSearch");
  const filter = document.getElementById("priceFilter");

  function apply() {
    const query = (search.value || "").toLowerCase();
    const priceFilter = filter.value;

    const filtered = rewards.filter((item) => {
      const matchesSearch = item.name.toLowerCase().includes(query) || item.tier.toLowerCase().includes(query);
      const matchesPrice =
        priceFilter === "all" ||
        (priceFilter === "low" && item.price < 500) ||
        (priceFilter === "mid" && item.price >= 500 && item.price <= 1200) ||
        (priceFilter === "high" && item.price > 1200);

      return matchesSearch && matchesPrice;
    });

    grid.innerHTML = filtered.map((item) => `
      <article class="reward-card">
        <div class="reward-art">${item.art}</div>
        <div class="reward-info">
          <h2>${item.name}</h2>
          <p class="muted">${item.tier} reward</p>
          <div class="reward-meta">
            <span class="price">${item.price} pts</span>
            <a class="button button-ghost" href="dashboard.html">Redeem</a>
          </div>
        </div>
      </article>
    `).join("");
  }

  search.addEventListener("input", apply);
  filter.addEventListener("change", apply);
  apply();
}

function initDashboard() {
  const balance = document.getElementById("balanceDisplay");
  const pending = document.getElementById("pendingDisplay");
  const userIdDisplay = document.getElementById("userIdDisplay");
  const tradeForm = document.getElementById("tradeForm");
  const tradeUrl = document.getElementById("tradeUrl");

  if (!balance) return;

  const userId = store.get("skinquest_user_id", null) || crypto.randomUUID();
  store.set("skinquest_user_id", userId);

  balance.textContent = "0";
  pending.textContent = "0";
  userIdDisplay.textContent = userId.slice(0, 8);

  tradeUrl.value = store.get("skinquest_trade_url", "");

  tradeForm.addEventListener("submit", (event) => {
    event.preventDefault();
    store.set("skinquest_trade_url", tradeUrl.value.trim());
    alert("Saved locally for now. In production this must save to your database.");
  });
}

initNav();
initOfferwall();
renderRewards();
initDashboard();
