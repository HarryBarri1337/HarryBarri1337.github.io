SkinQuest v12.3.0

What this release does
- Fixes the live reward claim failure by adding the missing redemption_requests.reward_id database column.
- Keeps the stable redeem_reward RPC and Steam Trade URL save flow.
- Adds a 15-second claim timeout, restores the Redeem button after every result, validates the RPC response, and shows useful error feedback.
- Removes duplicated rank numbers from level titles. For example, Level 7 now shows Corporal instead of Corporal Rank 7.
- Keeps clean URLs and campaign paths /01 through /05.
- Keeps every previous changelog entry instead of replacing release history.
- Includes the complete assets folder.

SQL files — exactly two
1. skinquest_upgrade_existing_to_v12_3_0.sql
   Run this ONCE on the current SkinQuest Supabase project. It adds the missing reward_id column, restores redeem_reward, and keeps the Trade URL repair.

2. skinquest_full_setup_v12_3_0.sql
   Use this only for a completely new Supabase project. Do not run it on the current live project.

Deployment order
1. Run skinquest_upgrade_existing_to_v12_3_0.sql in Supabase SQL Editor.
2. Upload the website files and replace the current deployment, including .htaccess, app.js, settings.html, changelog.html, sw.js, and the assets folder.
3. Hard-refresh with Ctrl + F5 or close/reopen the installed PWA.
4. Test one low-cost redemption. A successful test creates a redemption request, deducts the coins, reserves one reward, and adds a negative coin_adjustments row.
5. Confirm a level 7 account now displays Level 7 · Corporal.

Important
- Do not run the full setup SQL on the existing project.
- The website upload alone cannot repair claims. The upgrade SQL must be run on the existing Supabase project first.
- v12.2.8 through v12.2.10 are superseded by this repair.
