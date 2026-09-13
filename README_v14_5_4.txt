SkinQuest v14.5.4 — existing v14.5.3 upgrade
================================================
1. Back up your Supabase database.
2. Run ONLY skinquest_upgrade_existing_to_v14_5_4.sql in SQL Editor.
   Do not run full setup on an existing database.
3. Upload/replace the website files, then hard-refresh Admin.

No Edge Functions, Cron jobs, secrets, or schedules need changes.

WHAT CHANGED
- Fixed double focus highlights in Admin search inputs.
- Steam marketplace links now sit next to reward details, not among the action
  buttons. Three desktop actions fit on one line instead of making cases taller.
- Users: filter all roles, customers only (hides admins/owners), staff only,
  admins only, or owners only.
- Users: sort newest/oldest accounts, most/fewest coins, name, or owner/admin first.
- Users: show Steam sign-in accounts or exclude them. Connecting a Steam profile
  to an email account does not by itself classify it as a Steam sign-in account.
- Filtering and sorting apply server-side before pagination, not just to the
  first loaded users. Global search remains compatible.

REWARD DELETION REPAIR
The upgrade supports the older redemption_requests.reward_item_id foreign key,
backfills the canonical reward_id, and changes both supported links to SET NULL
on catalog deletion. Existing order names and coin amounts remain intact.
Conflicting non-null old/new links stop the upgrade transaction rather than
silently choosing an order's reward. Send that error if it occurs.
Open orders or reserved stock still block manual reward deletion. Steam-managed
items should be hidden because sync would recreate them.

Fresh projects use skinquest_full_setup_v14_5_4.sql.
Local JavaScript, package, and SQL consistency checks passed. Live SQL execution,
permissions, visual layout, and order workflows still require testing in your
Supabase project; no live changes were made while building this archive.
