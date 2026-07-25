SkinQuest v12.2.4

Release focus:
- Added all CS2 profile rank titles from Private Rank 1 through Global General and connected them to SkinQuest levels.
- Added animated +Coins and +XP popups when the site detects new earnings.
- Added a special level-up banner showing the newly unlocked level and CS2 profile rank title.
- Levels above 40 continue using the Global General title.
- Version references updated to v12.2.4. Cache-busting updated to styles.css?v=1224 and app.js?v=1224, with a refreshed service worker cache.

How the gain popup works:
- The first authenticated load saves a local progress snapshot without showing an old or oversized reward popup.
- Later increases to the wallet balance or lifetime earned amount trigger the animation.
- Earned coins increase both Coins and XP. Level reward bonuses increase Coins only.
- Progress snapshots are stored separately for each signed-in user in that browser.

Assets:
- No asset files were added or changed.

SQL:
- No schema or data changes are required in v12.2.4.
- skinquest_full_setup_v12_2_4.sql is the complete setup file for a fresh Supabase project.
- skinquest_upgrade_v12_2_4_from_v12_2_3.sql is included as a safe no-op version marker for existing v12.2.3 projects.

Completed setup notes:
- Support notification setup is already completed.
- Steam auth setup is already completed.
- Do not re-run those setup steps unless rebuilding the Supabase project from scratch.

Important:
- Supabase must have the correct email sender / SMTP settings configured if you want confirmation emails to come from your custom noreply address.
