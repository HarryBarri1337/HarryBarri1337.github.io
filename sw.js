// SkinQuest service worker - default PWA install support.
// Keeps things simple: same-origin GET requests use a stale-while-revalidate
// cache so the app can install and reopen quickly. Supabase/API calls and
// any cross-origin requests are always left alone and go straight to network.

const CACHE_NAME = "skinquest-cache-v1212";
const APP_SHELL = [
  "index.html",
  "dashboard.html",
  "rewards.html",
  "earn.html",
  "how-it-works.html",
  "styles.css?v=1212",
  "app.js?v=1212",
  "manifest.json",
  "assets/interface/skinquestlogo.png",
  "assets/interface/coin_logo.png",
  "assets/icons/icon-192.png",
  "assets/icons/icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(APP_SHELL))
      .catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((response) => {
          if (response && response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, clone)).catch(() => {});
          }
          return response;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
