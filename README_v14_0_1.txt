SkinQuest v14.0.1
=================

INSTALL ON THE EXISTING SKINQUEST SITE
1. Copy every file/folder in this package into the current SkinQuest project.
2. Replace existing files when prompted.
3. In Supabase SQL Editor, run the ENTIRE file:
   skinquest_upgrade_existing_to_v14_0_1.sql
4. Deploy/push the site normally.

FRESH SUPABASE PROJECT ONLY
Use:
   skinquest_full_setup_v14_0_1.sql
Do NOT run the full setup on the existing production database.

RELEASE PACKAGE RULE
- The ZIP is a complete current website, not a patch-only pack.
- Old README/release files are removed.
- Old SQL release files are removed.
- The upgrade SQL contains all database changes needed from the previous production version.
- The full SQL represents the complete current database setup.

v14.0.1 HOTFIX
- Restored the desktop navbar layout.
- Notifications now live inside the existing signed-in nav action area.
- Removed the dashboard-style live-data block from the homepage.
- The homepage uses the cleaner SkinQuest landing-page layout again.
