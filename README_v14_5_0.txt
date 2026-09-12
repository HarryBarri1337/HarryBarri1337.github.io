SkinQuest v14.5.0
=================

WHAT THIS BUILD ADDS
--------------------
v14.5.0 keeps the hardened v14.4.1 order lifecycle and adds a scalable Steam-
linked reward catalog. Prepared items and Available to order items now use the
same listing. Items SkinQuest owns show their available quantity; imported items
start as orderable with zero physical stock.

The Steam market is fetched only by the steam-market-sync Edge Function. The
browser never calls Steam directly, and the Supabase service key and scheduler
secret never appear in website JavaScript.

UPDATE AN EXISTING v14.4.1 PROJECT
---------------------------------
1. Back up the Supabase database.
2. Run skinquest_upgrade_existing_to_v14_5_0.sql ONCE in Supabase SQL Editor.
   This file contains only the v14.5.0 delta; do not rerun older upgrade files.
3. Deploy the new steam-market-sync Edge Function. supabase/config.toml disables
   platform JWT verification for this function because it validates either an
   owner JWT or STEAM_MARKET_SYNC_SECRET inside the function.
4. Add the Edge Function secret:
     STEAM_MARKET_SYNC_SECRET=<a long random secret>
5. Optional/recommended: create a Supabase Cron HTTP/Edge Function job every
   10 minutes:
   - Method: POST
   - Function: steam-market-sync
   - Header: x-steam-sync-secret: <same STEAM_MARKET_SYNC_SECRET>
   - Body: {"action":"catalog","max_pages":5}
6. Keep the existing v14.4.1 order functions and ORDER_CRON_SECRET deployment.
7. Upload/replace the public website files.
8. Hard-refresh and confirm the old service-worker cache is replaced by
   skinquest-cache-v1450.

BRAND-NEW SUPABASE PROJECT
--------------------------
Run skinquest_full_setup_v14_5_0.sql once, then deploy all Edge Functions in
supabase/functions. Do not also run the upgrade SQL on a new empty project.

FIRST CATALOG IMPORT
--------------------
1. Open Admin -> Rewards & stock as an Owner.
2. Review and save the pricing settings.
3. Click Sync next Steam batch. One click scans five Steam pages and saves the
   next cursor. Repeated clicks or the optional Cron job continue where the last
   successful batch stopped.
4. A full pass resets the cursor to zero. Later scheduled runs begin a new pass,
   refresh prices, and hide catalog-managed order items that no longer have a
   market listing. Prepared inventory is never auto-hidden by that cleanup.

The sync imports marketable CS2 weapon skins, knives, gloves, and cases that have
a positive Steam sell price. Stickers, graffiti, patches, agents, music kits,
charms, and other unrelated market entries are excluded.

PRICING MODEL
-------------
Steam values are stored as EUR cents. The default calculation is:

  ceil((Steam cents / 100) x coins per EUR x (1 + markup / 100))

Defaults:
- Markup: 15%
- Conversion: 100 coins per EUR
- Minimum: 1 coin
- Freshness window: 48 hours

All values can be changed by an Owner in Admin. Saving settings immediately
recalculates every Steam-linked reward from its last stored market price. Manual
price overrides are never changed by sync.

PRICE AND ORDER SAFETY
----------------------
- A Steam price is fetched and cached server-side; it is not trusted from the
  customer browser.
- If a linked price is missing or older than the configured freshness window,
  the listing can still be viewed but checkout is paused.
- The database checks freshness again inside the order transaction. A rejected
  stale-price order rolls back coin debit and stock reservation completely.
- redemption_requests already snapshots points_coins/points_cost, so changing a
  markup or later Steam price cannot rewrite a paid customer's order.
- Steam throttling or a failed page does not advance the saved catalog cursor.

INVENTORY + ORDER ITEMS
-----------------------
- Imported catalog items start as Available to order, quantity 0, and use the
  configured default ETA.
- To mark an item SkinQuest already owns, find that same catalog row in Admin,
  edit it to In stock / prepared, and enter total quantity. Do not create a
  duplicate listing.
- Prepared redemption reserves one available unit and starts Ready to trade.
- Orderable redemption leaves prepared inventory untouched and starts Ordered.
- Changing fulfilment mode or quantities remains protected by the v14.4.1
  database inventory guards.

LARGE-CATALOG SEARCH
--------------------
Rewards and Admin now use server-side search, filters, sorting, exact result
counts, and pagination. The website loads 48 customer cards at a time, while
Admin loads 75 rows at a time. Goal rewards continue to load directly by ID.

MANUAL / CUSTOM REWARDS
-----------------------
Use Add custom reward for items that should not follow Steam. Select Manual coin
price. To return an imported item to automatic pricing, select Steam linked; it
must already have a stored Steam price and exact market name.

REQUIRED / OPTIONAL SECRETS
---------------------------
Existing order email and trade-lock secrets remain unchanged:
- RESEND_API_KEY
- ADMIN_REWARD_EMAIL
- EMAIL_FROM (optional)
- ORDER_CRON_SECRET (for reward-order-ready-sweep)

New for automatic catalog scheduling:
- STEAM_MARKET_SYNC_SECRET

DEPLOYMENT ORDER
----------------
Database first, Edge Functions second, website files last. This order ensures
the paginated catalog RPCs and pricing columns exist before v14.5.0 JavaScript
requests them.

Steam can rate-limit or change its public Community Market responses. v14.5.0
fails closed: it keeps the previous cursor and pauses stale linked prices instead
of guessing a value. Use the Admin sync status and RELEASE_CHECKS_v14_5_0.txt
after deployment.
