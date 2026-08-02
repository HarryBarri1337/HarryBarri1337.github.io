SkinQuest v12.2.9

Purpose
-------
This release repairs the complete Trade URL and reward redemption path.
The previous v12.2.8 existing-project SQL only patched Trade URL saving and did
not synchronize the redemption schema or redeem_reward RPC. Do not use the old
v12.2.8 upgrade file.

SQL files in this package
-------------------------
1. skinquest_upgrade_existing_to_v12_2_9.sql
   Run this on the CURRENT Supabase project. It preserves existing data and
   synchronizes the complete SkinQuest database: tables, missing columns,
   functions, policies, grants, views, redemption logic, and schema cache.

2. skinquest_full_setup_v12_2_9.sql
   Use only for a completely new Supabase project.

There are no older upgrade SQL files in this package.

Deployment order
----------------
1. Open Supabase > SQL Editor.
2. Run skinquest_upgrade_existing_to_v12_2_9.sql and confirm it finishes without an error.
3. Upload all website files from this package to the web root.
4. Make sure .htaccess is uploaded.
5. Hard-refresh with Ctrl+F5 or clear the site's service-worker cache.
6. Save a Steam Trade URL, reload Settings, and confirm it remains saved.
7. Redeem a test reward. If Supabase still rejects it, the site now displays the
   actual database reason instead of hiding it behind a generic message.

Main changes
------------
- Replaced redeem_reward(bigint) with an atomic, validated redemption function.
- Removed old integer/numeric/text redeem_reward overloads that can confuse PostgREST.
- Added/repaired all required redemption and coin-ledger columns.
- Refreshed the PostgREST schema cache after SQL deployment.
- Added detailed frontend error handling and a Redeeming state with timeout recovery.
- Updated asset cache-busting and the service worker to 1229.
