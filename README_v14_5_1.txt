SkinQuest v14.5.1 — update an existing v14.5.0 installation
==========================================================
Your assumed live state: v14.5.0 database and website already installed; the
steam-market-sync function is the earlier deployment (without per-page progress
and detailed errors). Your Cron job already exists. The optional
reward-order-ready-sweep is NOT required, and need not be deployed.

Do this in order:
1. Back up your Supabase database.
2. In Supabase SQL Editor run ONLY skinquest_upgrade_existing_to_v14_5_1.sql.
   Do not run skinquest_full_setup_v14_5_1.sql or any earlier upgrade again.
3. Upload the website files in this package; reload /admin after upload.
4. Open a Ready to trade order, leave Steam trade offer URL empty, choose Trade
   sent, confirm that the real Steam offer has been sent, and save. The customer
   trade URL is separate: use its Copy/Open buttons to send the offer.
5. After the customer accepts in Steam, change Trade sent to Completed.
   If the offer expires/declines, move it back to Ready to trade instead.

Steam sync function (separate fix INCLUDED, not yet deployed by you):
- Your existing steam-market-sync and Cron continue as before if you leave them
  untouched. This v14.5.1 package includes the previously prepared function
  fix: successful pages save individually and sync errors show more detail.
- To apply it, open Edge Functions -> steam-market-sync in Supabase, replace its
  code with supabase/functions/steam-market-sync/index.ts, then Deploy updates.
  Keep Verify JWT off, and keep the existing Cron schedule, URL, headers and
  STEAM_MARKET_SYNC_SECRET unchanged. Do not paste the secret into code.
- This fix does NOT increase import speed; it just improves progress and errors.
  If catalog sync is currently failing, deploy it and read the resulting Admin
  error. No additional SQL or website changes are needed for this function fix.

No other Edge Function requires deployment for the redeem fix. If you never
installed reward-order-ready-sweep, do not install it merely for this release.
New installations may use skinquest_full_setup_v14_5_1.sql, whose final Admin
order function has the v14.5.1 rule.

Local validation checks syntax and package consistency. Live database behavior,
Steam API responses and customer email delivery require testing in Supabase.
