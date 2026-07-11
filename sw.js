// SkinQuest service worker - default PWA install support.
// Same-origin GET requests use network-first: always try the network so
// deployed updates show up immediately, and only fall back to the cache
// when offline. Supabase/API calls and any cross-origin requests are
// always left alone and go straight to network.

const CACHE_NAME = "skinquest-cache-v1223";
const APP_SHELL = [
  "index.html",
  "dashboard.html",
  "rewards.html",
  "earn.html",
  "how-it-works.html",
  "styles.css?v=1223",
  "app.js?v=1223",
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
    fetch(request)
      .then((response) => {
        if (response && response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, clone)).catch(() => {});
        }
        return response;
      })
      .catch(() => caches.match(request))
  );
});
