SkinQuest v11.8.1 - Reward toolbar hotfix

Install / upload:
1. Upload these files over your current SkinQuest v11.8 files.
2. Keep your existing assets folder. This release does not include assets.
3. Make sure assets/interface/skinquestlogo.png still exists in your own assets folder.

Changes in v11.8.1:
- Removed the ugly browser number arrows from Min coins / Max coins inputs.
- Price range inputs now behave like clean text inputs but only keep numbers.
- Tightened the Availability filter pills so they stay on one clean row on desktop.
- Kept the v11.8 custom sort menu and reward filtering flow.

SQL:
- No database changes are required from v11.8.
- skinquest_upgrade_v11_8_1_from_v11_8.sql is a no-op marker.
- skinquest_full_setup_v11_8_1.sql is the full setup file for a fresh Supabase project.

Assets:
- No assets folder is included. Use your existing assets package.
