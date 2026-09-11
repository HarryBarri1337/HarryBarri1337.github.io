SkinQuest v14.3.0
=================

UPDATE AN EXISTING v14.2.0 PROJECT
----------------------------------
1. Back up the Supabase database.
2. Run skinquest_upgrade_existing_to_v14_3_0.sql ONCE in Supabase SQL Editor.
3. Redeploy these existing Edge Functions from the included files:
   - support-submit
   - reward-order-notify
4. Upload/replace the public website files with this version.
5. Hard-refresh the website (Ctrl+Shift+R) so the v14.3.0 assets replace the old cache.

The upgrade SQL contains only v14.3.0 changes. No Edge Function is added and no new
secret is required. The two existing functions above are updated so customer-facing
confirmations and reward emails use the new case numbers.

FOR A BRAND-NEW EMPTY SUPABASE PROJECT
--------------------------------------
Run skinquest_full_setup_v14_3_0.sql once, then deploy every Edge Function inside
supabase/functions. Do not run both SQL files on a new project.

WHAT CHANGED
------------
- Admin is now a separate operations workspace instead of one long customer-style page.
- Its navigation includes Overview, Redeem orders, Support inbox, Rewards & stock,
  Add reward, System status, Promo codes, Audit trail, Coin adjustments, and Team access.
- Redeem requests receive stable numbers such as SQ-R-000001.
- Support requests receive stable numbers such as SQ-S-000001.
- Customers see redeem numbers in confirmations, dashboards, and reward emails, and
  see their support ticket number immediately after a successful submission.
- Admins can search current and historical cases by number, customer, email, reward,
  topic, message, user ID, or admin note.
- Case drawers show the full record, safe links, quick actions, internal notes,
  responsible admin, and case activity.
- Completed orders record completed_by. Every handled order records last_handled_by.
- Resolved support tickets record resolved_by. Every handled ticket records
  last_handled_by.
- Order, support, team-role, coin, reward, promo, and system-status actions feed the
  audit trail.

SECURITY MODEL
--------------
- The page checks the signed-in user against admin_users, but the browser check is
  only presentation. Supabase RLS and SECURITY DEFINER RPCs enforce real access.
- Redeem and support changes validate admin access again on the server.
- Direct browser UPDATE permission on support_requests is removed; admins use the
  audited support RPC.
- System-status and promo-code mutations are RPC-only, so browser clients cannot
  bypass their audit trail with direct table writes.
- Finished, rejected, refunded, and cancelled reward orders cannot be reopened.
  This protects coin refunds and inventory from being applied twice.
- Reward writes, coin corrections, and team-access changes remain owner-only.
- The final owner cannot be removed or demoted.
- Coin corrections require a reason, reject negative resulting balances, and record
  both previous and resulting balances.
- Stored external links are opened only when they match trusted HTTPS Steam or
  SkinQuest hosts.

IMPORTANT
---------
Run the upgrade SQL before using the new Admin workspace. The interface has a limited
read-only compatibility fallback for old case lists, but handler tracking, case-number
search, support updates, and the hardened workflow require the v14.3.0 migration.

This release intentionally does not add the planned "Available to order / Trade locked
/ Ready to trade" purchasing workflow. That workflow remains a later, separate stage.
