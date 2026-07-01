SkinQuest v11.8.2 - Pre-meeting polish hotfix

Install / upload:
1. Upload these files over your current SkinQuest v11.8.1 files.
2. Keep your existing assets folder. This release does not include assets.
3. Make sure assets/interface/skinquestlogo.png and your existing reward/interface images are still in your own assets folder.

Changes in v11.8.2:
- Removed the Need more coins availability chip from the Rewards toolbar.
- Tightened the Availability filter layout so All rewards, Can afford, and In stock fit together cleanly.
- Hid unfinished Steam/Google v12 sign-in buttons in the auth modal.
- Reduced unfinished linked-service placeholders in Settings.
- Hid the Admin nav link by default in HTML until JS confirms the signed-in user is an admin.
- Fixed trade URL copy so it points users to Settings instead of Dashboard.
- Added changelog entries for v11.8.1 and v11.8.2.

SQL:
- No database changes are required from v11.8.1.
- skinquest_upgrade_v11_8_2_from_v11_8_1.sql is a no-op marker.
- skinquest_full_setup_v11_8_2.sql is the full setup file for a fresh Supabase project.

Assets:
- No assets folder is included. Use your existing assets package.
