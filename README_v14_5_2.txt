SkinQuest v14.5.2 — upgrade an existing v14.5.1 installation
================================================================

This release assumes v14.5.1 is already live.

WHAT CHANGED
- Admin now has a searchable Users page. Search by verified email, username,
  Steam name, Steam ID, or SkinQuest user ID.
- The generic SQ admin badge was replaced with the existing SkinQuest logo.
- Owners can permanently delete manually created rewards that have never been
  used in an order and have no reserved stock.
- Owners can permanently delete promo codes that have never been redeemed.
- Steam-managed rewards and all records with customer history remain protected.
- Deletions are recorded in the admin audit trail.

UPGRADE ORDER
1. Back up the Supabase database.
2. In SQL Editor run ONLY skinquest_upgrade_existing_to_v14_5_2.sql.
   Do not run the full setup on an existing database.
3. Upload/replace the website files from this archive.
4. Reload Admin and test Users, one unused manual reward, and one unused promo.

NO EDGE FUNCTION CHANGES ARE REQUIRED FOR v14.5.2.
Leave steam-market-sync, its Cron job, headers, secret, and schedule unchanged.

Fresh installations can use skinquest_full_setup_v14_5_2.sql.
Local syntax and package checks are included; live database permissions and
deletion protection must still be verified in your Supabase project.
