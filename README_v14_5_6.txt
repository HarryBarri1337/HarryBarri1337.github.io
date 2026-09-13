SkinQuest v14.5.6 — upgrade from live v14.5.5
============================================
1. Back up your Supabase database.
2. Run ONLY skinquest_upgrade_existing_to_v14_5_6.sql.
   Never run full setup on an existing installation.
3. Upload the website files and hard-refresh the browser.

No Edge Function, Cron, or secret changes are required.

Users: compact directory with creation date, last active, coins, existing
role/login filters and sorting. View user opens a single account view with
orders, coin history, promo redemptions, survey results and support (25 per page).

Last active uses server timestamps from visible, recently interacted-with pages.
Checks run every minute; hidden tabs and tabs idle for over five minutes stop
updating. Existing daily/product activity is used when available. Unknown means
no recorded activity, not never logged in. This is not a live online indicator.

CPX launch tracking fixed: the Supabase RPC builder has no catch method; the
request is now consumed as a Promise. No historical launch counts are invented.
CPX results show completed reward postbacks separately from CPX-labelled coin
ledger credits. These sources are never added together (they can overlap).
Legacy ledger labels are evidence, not verified survey-completion proof.
Missing records display No records, not a claim of zero completed surveys.
Reward postbacks can include compensation; they do not prove full surveys.
Launch clicks mean the Open CPX button, not survey opens inside the CPX widget.
If data remains missing, run read-only CPX_DIAGNOSTICS_v14_5_6.sql to inspect
provider/status/source counts before changing the CPX integration.

Fresh installations use skinquest_full_setup_v14_5_6.sql.
Local JavaScript/package checks performed; SQL not executed against a database.
Live permissions, CPX callbacks, and presence need deployment testing.
No live website or database was modified while preparing this archive.
