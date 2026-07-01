SkinQuest v11.6 - Nav & auth cleanup

Use this version as a small pre-v12 polish release.

Changes from v11.5:
- Removed Settings from the top navbar. Settings is now reached from the account dropdown and in-page buttons.
- Cleaned the account/profile dropdown so level is not duplicated there. The separate level pill in the nav remains the source of truth.
- Added a confirmation modal before logging out from both nav dropdown and dashboard.
- Improved signup copy so existing emails are not shown as clearly “created new”. It now tells users to check inbox or sign in if they already have an account.
- Updated footer/changelog/cache version to v11.6.

SQL:
- skinquest_full_setup_v11_6.sql = full setup for a fresh Supabase project.
- skinquest_upgrade_v11_6_from_v11_5.sql = no-op upgrade marker. No database changes are needed from v11.5.

Assets:
- This zip does NOT include the assets folder. Keep using your local assets folder:
  assets/interface/site-background.png
  assets/interface/coin_logo.png
  assets/rewards/...
