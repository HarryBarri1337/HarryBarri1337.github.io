SkinQuest v14.4.1
=================

WHAT THIS BUILD FIXES
---------------------
v14.4.1 is the hardened version of the v14.4 order system. It keeps the two
fulfilment modes but removes unsafe status skipping, protects inventory mode
changes, improves customer status text, retries missed status emails from Admin,
and adds an optional scheduled sweep so expired Steam trade locks do not depend
on somebody opening the Admin page.

UPDATE AN EXISTING v14.3.0 OR v14.4.0 PROJECT
---------------------------------------------
1. Back up the Supabase database.
2. Run skinquest_upgrade_existing_to_v14_4_1.sql ONCE in Supabase SQL Editor.
   - It is safe to use this build if v14.4.0 was not deployed yet.
   - It is also designed to replace/harden the v14.4.0 functions if you already
     tested v14.4.0.
3. Deploy/redeploy:
   - reward-order-notify
   - reward-order-status-notify
   - delete-account
4. Deploy reward-order-ready-sweep if you want automatic trade-lock expiry
   notifications without waiting for an Admin page refresh.
5. Upload/replace the public website files.
6. Hard-refresh so the v14.4.1 cache replaces older assets.

BRAND-NEW SUPABASE PROJECT
--------------------------
Run skinquest_full_setup_v14_4_1.sql once, then deploy all Edge Functions in
supabase/functions. Do not run both SQL files on a new empty project.

ORDER MODES
-----------
IN STOCK / PREPARED
- SkinQuest already owns the item.
- One physical unit is reserved when the order is created.
- The order starts Ready to trade.
- Normal flow: Ready to trade -> Trade sent -> Completed.
- Completing consumes exactly one reserved unit.
- Reject/refund/cancel BEFORE Trade sent returns coins once and releases the unit.

AVAILABLE TO ORDER
- Can remain visible/orderable with physical stock 0.
- Never consumes or reserves prepared inventory.
- Coins are deducted immediately.
- Normal flow: Ordered -> Trade locked -> Ready to trade -> Trade sent -> Completed.
- Purchased / Trade locked requires Steam's exact FUTURE unlock time.
- Customer sees the exact live countdown once purchased.
- Reject/refund/cancel is allowed before the trade has been sent.

IMPORTANT SAFETY CHANGE
-----------------------
The database now enforces the order transition graph. The browser is not trusted
to decide valid transitions.

Examples that are now rejected server-side:
- Ordered -> Completed
- Ordered -> Trade sent
- Prepared reward -> Trade locked
- Ready to trade -> Completed without first recording Trade sent
- Trade sent -> Refunded / Cancelled / Rejected

If a Steam offer is declined or expires after being sent, move:
  Trade sent -> Ready to trade
Then send a new offer. This avoids accidentally giving both the item and a refund.

INVENTORY SAFETY
----------------
- Total and reserved stock can never be negative.
- Reserved cannot exceed total.
- A stocked reward with reserved units cannot be switched to Available to order.
- Orderable rewards do not touch prepared stock when ordered/completed/refunded.
- Refunds remain protected by refunded_at so the same order cannot credit twice.

AUTOMATIC TRADE-LOCK EXPIRY (RECOMMENDED)
-----------------------------------------
Without the scheduled sweep, Admin still refreshes expired locks safely when the
operations workspace is opened/refreshed. v14.4.1 additionally includes:
  supabase/functions/reward-order-ready-sweep

This can be run by Supabase Cron every 5 minutes. The function:
1. Finds only expired Trade locked orders.
2. Changes them to Ready to trade atomically.
3. Sends READY TO TRADE to ADMIN_REWARD_EMAIL.
4. Sends the customer Ready to trade email when a valid contact email exists.
5. Leaves failed notifications retryable from the Admin workspace.

Required Edge Function secret:
  ORDER_CRON_SECRET=<a long random secret>

Deploy reward-order-ready-sweep with JWT verification disabled because the
function authenticates the scheduler using x-cron-secret itself. Do NOT expose
ORDER_CRON_SECRET in website JavaScript.

Then create a Supabase Cron HTTP/Edge Function job (recommended every 5 minutes):
- Method: POST
- Function: reward-order-ready-sweep
- Header: x-cron-secret: <same ORDER_CRON_SECRET>
- Body: {}

Supabase Cron supports recurring Edge Function / HTTP jobs. If you do not enable
this optional job, the rest of v14.4.1 still works; expired locks are refreshed
when Admin refreshes.

EMAIL SECRETS
-------------
Existing:
- RESEND_API_KEY
- ADMIN_REWARD_EMAIL
- EMAIL_FROM (optional)

New only for the scheduled sweep:
- ORDER_CRON_SECRET

ADMIN UX IMPROVEMENTS
---------------------
- The status dropdown shows only the current status + valid next steps.
- Quick actions are generated from the same safe flow.
- Trade-lock input is disabled for prepared rewards.
- Order ETA is only editable for Available to order rewards.
- Prepared stock fields are disabled while editing an Available to order reward.
- Valid Steam trade proof now requires an actual numeric /tradeoffer/<id>/ URL.
- Admin retries missed status notifications for actionable order states.
- Order drawer explains that sent trades cannot be refunded from the normal flow.

CUSTOMER UX IMPROVEMENTS
------------------------
- Ordered rewards show the initial ETA when available.
- Trade locked shows both countdown and exact unlock date/time.
- Trade sent explains what happens if an offer expires/gets declined.
- Closed/refunded orders explicitly explain that refunds are server-controlled.

DEPLOYMENT ORDER
----------------
Database first, Edge Functions second, website files last.
The v14.4.1 frontend expects the v14.4.1 RPCs/columns to exist.
