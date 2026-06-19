// SkinQuest frontend prototype.
// WARNING: This is NOT secure for real payouts.
// Real survey rewards must be credited by a backend webhook/postback from your offerwall provider.

const OFFERWALL_URL = "https://example.com/your-offerwall-url?user_id=";
// Replace the URL above with your provider URL from BitLabs, CPX, Pollfish, etc.
// Never credit coins just because a user clicked a button.

const state = {
  balance: Number(localStorage.getItem("coinBalance") || 0),
  tradeUrl: localStorage.getItem("tradeUrl") || "",
  redeems: JSON.parse(localStorage.getItem("redeems") || "[]")
};

const skins = [
  {
    id: "p250-sand-dune",
    name: "P250 | Sand Dune",
    rarity: "Starter skin",
    price: 120,
    icon: "🔫"
  },
  {
    id: "usp-ticket",
    name: "USP-S | Ticket to Hell",
    rarity: "Budget skin",
    price: 350,
    icon: "🎯"
  },
  {
    id: "ak-slate",
    name: "AK-47 | Slate",
    rarity: "Popular skin",
    price: 900,
    icon: "⚡"
  },
  {
    id: "m4a1-night-terror",
    name: "M4A1-S | Night Terror",
    rarity: "Mid skin",
    price: 1100,
    icon: "🌙"
  },
  {
    id: "awp-atheris",
    name: "AWP | Atheris",
    rarity: "AWP skin",
    price: 1500,
    icon: "🐍"
  },
  {
    id: "knife-ticket",
    name: "Knife raffle ticket",
    rarity: "Manual promo idea",
    price: 2500,
    icon: "🎟️"
  }
];

const balanceEl = document.getElementById("coinBalance");
const skinsGrid = document.getElementById("skinsGrid");
const redeemList = document.getElementById("redeemList");
const tradeUrlInput = document.getElementById("tradeUrl");

function saveState() {
  localStorage.setItem("coinBalance", String(state.balance));
  localStorage.setItem("tradeUrl", state.tradeUrl);
  localStorage.setItem("redeems", JSON.stringify(state.redeems));
}

function renderBalance() {
  balanceEl.textContent = state.balance.toLocaleString();
}

function renderSkins() {
  skinsGrid.innerHTML = "";

  skins.forEach((skin) => {
    const card = document.createElement("article");
    card.className = "card skin-card";

    const canAfford = state.balance >= skin.price;

    card.innerHTML = `
      <div class="skin-image">${skin.icon}</div>
      <div class="skin-meta">
        <div>
          <h3>${skin.name}</h3>
          <p>${skin.rarity}</p>
        </div>
        <span class="price">${skin.price} coins</span>
      </div>
      <button class="button primary" ${canAfford ? "" : "disabled"} data-redeem="${skin.id}">
        ${canAfford ? "Redeem" : "Need more coins"}
      </button>
    `;

    skinsGrid.appendChild(card);
  });

  document.querySelectorAll("[data-redeem]").forEach((button) => {
    button.addEventListener("click", () => {
      const skin = skins.find((item) => item.id === button.dataset.redeem);
      redeemSkin(skin);
    });
  });
}

function renderRedeems() {
  redeemList.innerHTML = "";

  if (state.redeems.length === 0) {
    redeemList.innerHTML = `<div class="panel">No redeem requests yet.</div>`;
    return;
  }

  state.redeems.forEach((redeem) => {
    const item = document.createElement("div");
    item.className = "redeem-item";
    item.innerHTML = `
      <div>
        <strong>${redeem.skinName}</strong>
        <p>${redeem.createdAt}</p>
      </div>
      <span class="status">${redeem.status}</span>
    `;
    redeemList.appendChild(item);
  });
}

function redeemSkin(skin) {
  if (!state.tradeUrl) {
    alert("Save your Steam trade URL before redeeming.");
    return;
  }

  if (state.balance < skin.price) {
    alert("Not enough coins.");
    return;
  }

  state.balance -= skin.price;

  state.redeems.unshift({
    skinId: skin.id,
    skinName: skin.name,
    cost: skin.price,
    tradeUrl: state.tradeUrl,
    status: "Pending review",
    createdAt: new Date().toLocaleString()
  });

  saveState();
  render();
  alert("Redeem request created. In a real site, an admin or bot would send the skin after review.");
}

function render() {
  renderBalance();
  renderSkins();
  renderRedeems();
  tradeUrlInput.value = state.tradeUrl;
}

document.getElementById("openSurveyWall").addEventListener("click", () => {
  const demoUserId = "demo_user_123";
  window.open(OFFERWALL_URL + encodeURIComponent(demoUserId), "_blank");
});

document.getElementById("demoReward").addEventListener("click", () => {
  state.balance += 80;
  saveState();
  render();
});

document.getElementById("profileForm").addEventListener("submit", (event) => {
  event.preventDefault();
  state.tradeUrl = tradeUrlInput.value.trim();
  saveState();
  render();
  alert("Trade URL saved.");
});

render();
