SkinQuest v14.0.0
=================

THIS PACKAGE IS A COMPLETE WEBSITE VERSION.
Copy the whole folder over your current SkinQuest website and replace matching files.
No Node script or injector is needed.

YOUR CURRENT / EXISTING SKINQUEST DATABASE
------------------------------------------
This is the normal option for the live SkinQuest site.

1. Back up the website and Supabase database.
2. Copy/upload ALL files and folders from this package over the current site.
3. Open Supabase -> SQL Editor.
4. Open:
      skinquest_upgrade_existing_to_v14_0_0.sql
5. Copy the ENTIRE file into Supabase SQL Editor and press Run.
6. Deploy/push the website normally.
7. Purge the host/CDN cache and reopen any installed SkinQuest PWA.

The upgrade SQL is additive and is designed for the existing v13.1.0 database.
It is safe to rerun if a deployment attempt is interrupted.

IMPORTANT: DO NOT run skinquest_full_setup_v14_0_0.sql on the existing production database.

NEW / EMPTY SUPABASE PROJECT ONLY
---------------------------------
For a completely fresh Supabase project, use ONLY:
      skinquest_full_setup_v14_0_0.sql

That full file contains the complete SkinQuest database setup through v14.0.0,
including the v13.1.0 base schema and every v14 database addition.
Do not run the upgrade SQL afterwards on a fresh project that used the full setup.

FILES CLEANED UP IN THIS RELEASE
--------------------------------
- Old v13.1.0 README removed.
- Old v13.1.0 release-check file removed.
- Old v13.1.0 full SQL removed and replaced by the v14 full SQL.
- Old v13.1.0 upgrade SQL removed and replaced by the v14 upgrade SQL.
- Duplicate RUN_THIS / README patch-pack files removed.
- Existing assets, .github files, Supabase Edge Functions, and other project folders are preserved.

V14.0.0 ADDS
------------
- Quests, achievements, onboarding progress, and activity streaks.
- In-app notifications for earnings and reward status changes.
- Reward restock subscriptions.
- Promotional / QR codes.
- Referral attribution without a signup payout.
- Campaign attribution and product funnel events.
- Public homepage statistics and recently completed reward proof.
- More reward filters, balance progress, and reward details.
- Admin KPIs, system status controls, and reward audit logging.
- Consent-controlled analytics and cookie preferences.
- Offline status/fallback, mobile bottom navigation, and accessibility polish.

UNCHANGED / PRESERVED
---------------------
- Existing CPX and BitLabs provider flow.
- Existing Steam authentication and trade URL flow.
- Existing secure redemption authority and reward accounting.
- Existing v13.1.0 Supabase Edge Functions and secrets.
- Existing assets and deployment workflow.
