SkinQuest v12.2.10

What this release does
- Backtracks reward redemption to the v12.2.4 frontend and redeem_reward RPC that was confirmed working.
- Keeps clean URLs and campaign paths /01 through /05.
- Fixes the Steam Trade URL Save button without rewriting the rest of the redemption database.
- Keeps every previous changelog entry instead of replacing release history.
- Includes the complete assets folder.

SQL files — exactly two
1. skinquest_upgrade_existing_to_v12_2_10.sql
   Run this ONCE on the current SkinQuest Supabase project. It restores the stable redeem_reward RPC and repairs only the Trade URL save path.

2. skinquest_full_setup_v12_2_10.sql
   Use this only for a completely new Supabase project. Do not run it on the current live project.

Deployment order
1. Run skinquest_upgrade_existing_to_v12_2_10.sql in Supabase SQL Editor.
2. Upload the website files and replace the current deployment, including .htaccess, app.js, settings.html, changelog.html, sw.js, and the assets folder.
3. Hard-refresh with Ctrl + F5 or close/reopen the installed PWA.
4. In Settings, save a valid Steam Trade URL and confirm the button immediately shows Saving, then Saved.
5. Reload Settings and confirm the Trade URL remains saved.
6. Test one redemption.

Important
- Do not run the full setup SQL on the existing project.
- v12.2.8 and v12.2.9 are superseded by this focused repair.
