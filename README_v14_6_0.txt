SkinQuest v14.6.0 — from live v14.5.7
=====================================

INSTALL ON YOUR EXISTING SITE
1. Take a database backup and keep your currently deployed website files.
2. In Supabase SQL Editor, run ONLY skinquest_upgrade_existing_to_v14_6_0.sql.
   Do NOT run the full setup or earlier migrations on an existing database.
   The delta adds records/search/customer RPCs. It does not reset coins,
   orders, stock, achievements, users, sync progress, secrets or Cron jobs.
   Generated catalogue columns/indexes can take longer on a large catalogue.
3. Upload the new website files, including reward.html, order.html,
   support.html, skinquest-v146.js, skinquest-v146.css and the new .htaccess.
   Keep your actual Supabase URL/anon configuration if you use a different project.
   Do not put SQL, README, checks, provider guidance or supabase/ into your public web root.
4. Hard-refresh and test one real account before announcing the update.

NO EDGE FUNCTION, SECRET OR CRON CHANGE IS REQUIRED FOR THIS RELEASE.
Do not deploy the copied legacy Edge Functions just because they are in the ZIP.
In particular, keep your currently deployed steam-market-sync and current
Cron schedule. This version does NOT speed up or replace the Steam import.

YOUR SELECTED FEATURES
2  First reward: low-cost live examples, stock/price-safe recommendations,
   starter sort and a goal-to-redemption journey without promised earning times.
4  Owner > Finance & funding: manual EUR receipts, expected provider payments,
   expenses, purchase/order costs, owner funding, operating cash difference,
   unknown-cost warnings, duplicate references and audited void corrections.
   No automatic revenue import; not a bank balance, formal accounts or tax report.
5  Own order page /orders/ID: saved item/coins, actual status, recorded dates,
   exact trade-lock countdown, customer update, safe Steam-offer link and support.
10 Clearer homepage: actual catalogue examples and transparent delivery flow.
   No fabricated deliveries, user reviews, earnings claims or public user records.
11 Coin history: source filters, server pagination, actual refunds/reversals,
   transaction references and owned-order links. Legacy unlabelled records may
   remain Adjustments; promo reasons and existing level_reward records are recognised.
12 Personal next move: account status, email, sent trade, trade URL, open order,
   goal/current balance, then an available starter reward.
14 One skin-family catalogue card with exact wear/StatTrak/Souvenir options.
   Toggle grouping off to see individual listings. Inventory/order fallback
   remains per exact listing: prepared stock is used first. No duplicate listing
   is created just by adding quantity to an existing imported listing.
15 Permanent /rewards/ID pages with copy link, saved goal, exact selected item,
   current price, stock, delivery details and authenticated redeem confirmation.
   These are static shells populated from Supabase. They are NOT a server-rendered
   SEO catalogue or a promise that all social preview crawlers execute JavaScript.
16 Search tokens in any order, weapon/wear aliases, prefixes and one-character
   insertion/deletion/substitution tolerance. Keyboard-accessible live suggestions.
   Existing weapon/wear/rarity filters now request server results across the catalogue.
19 Loading, reported-empty, connection-error and unknown availability states.
   A loaded script is not proof of survey availability; zero NEW surveys does
   not hide existing surveys. A browser callback cannot credit coins.
20 /support: verified account contact, optional owned order/coin transaction,
   immutable context snapshot, retry identifier and recent ticket status.
   Tickets appear in Admin. Email alerts still require your existing support
   INSERT webhook/support-notify setup; this release does not create one.
18 HELP: read SECOND_PROVIDER_v14_6_0.md. Torox is the first application to
   consider, Lootably another option. No second provider is activated yet.

ORDER NOTES
The new Customer order-page update is stored separately. It is displayed on
private order pages and the dashboard. The legacy Admin note can still appear
in your EXISTING notification emails, so do not put secrets/private staff data
there. Existing Edge Function email behaviour is unchanged.

ROUTES / HOSTING
The included Apache/LiteSpeed .htaccess adds /rewards/ID, /orders/ID and /support.
If your host does not use .htaccess, configure equivalent rewrites to reward.html,
order.html and support.html. Numeric IDs are stable; the browser also supports
reward.html?id=ID / order.html?id=ID for diagnostics. Nested page assets use a
root base URL. Deployment assumes your existing root-domain hosting.
Private order/dashboard/settings/support/admin HTML is not retained by the
updated service worker. Supabase/API calls remain uncached.

VERIFICATION
See RELEASE_CHECKS_v14_6_0.txt for local tests and live deployment checks.
Local tests use embedded PostgreSQL with stubbed Supabase auth and Chromium
with mock API data; they do NOT touch or prove your live environment.
Only a BRAND-NEW installation uses skinquest_full_setup_v14_6_0.sql.
