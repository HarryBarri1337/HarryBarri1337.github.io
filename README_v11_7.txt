SkinQuest v11.7 - Logo & reward shop polish

Use this version as a front-end polish release before deeper testing.

Changes from v11.6:
- Applied the header brand logo from assets/interface/skinquestlogo.png.
- Kept the existing loading bar behavior as-is.
- Rebuilt the Rewards toolbar layout so Search, Price, Availability, and Sort sit correctly together instead of pushing Sort/price controls onto awkward rows.
- Added labels and a cleaner panel style to the reward filter/sort controls.
- Added smoother reward-grid refresh behavior when changing filters, sorting, or typing in search.
- Prevented duplicate reward filter event listeners from stacking when rewards reload.
- Updated footer/changelog/cache version to v11.7.

SQL:
- skinquest_full_setup_v11_7.sql = full setup for a fresh Supabase project.
- skinquest_upgrade_v11_7_from_v11_6.sql = no-op upgrade marker. No database changes are needed from v11.6.

Assets:
- This zip does NOT include the assets folder.
- Keep using your existing assets folder.
- Required existing/new asset path for the logo:
  assets/interface/skinquestlogo.png
- Existing asset paths still used:
  assets/interface/site-background.png
  assets/interface/coin_logo.png
  assets/rewards/...
