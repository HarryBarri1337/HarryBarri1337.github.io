SkinQuest v12.1.2

Release focus:
- Added PWA support: SkinQuest can be installed to a phone or desktop home screen (manifest.json + sw.js + icons).
- Added goal rewards: star up to 5 rewards on the Rewards page (star icon on each card).
- Added a "Goal rewards" section on the dashboard, shown once at least one reward is starred, with a picture, name, and coin progress bar for each starred reward.
- When you have enough coins for a starred reward, its progress bar is replaced with a Claim reward button that opens Rewards with that item already searched.
- Version references updated to v12.1.2.
- Cache-busting updated to styles.css?v=1212 and app.js?v=1212.

Assets:
- Not included in this package.
- Keep your existing assets/interface files on the server.
- New: assets/icons/ (PWA icons) must be uploaded alongside the rest of assets/.

New files in this release:
- manifest.json (PWA web app manifest)
- sw.js (service worker, same-origin app shell caching only)
- assets/icons/icon-192.png, icon-512.png, icon-maskable-192.png, icon-maskable-512.png, apple-touch-icon.png, favicon-32.png, favicon-16.png

Excluded from package:
- .git
- .github
- supabase
- assets

SQL:
- Full setup SQL is included (skinquest_full_setup_v12_1_2.sql).
- Upgrade SQL is included (skinquest_upgrade_v12_1_2_from_v12_1_1.sql).
- Schema change in v12.1.2: new favorite_rewards table (goal rewards), with RLS and a 5-per-user limit trigger.
- Run the upgrade SQL once on your existing Supabase project. It only contains what changed since v12.1.1.

Completed setup notes:
- Support notification setup is already completed.
- Steam auth setup is already completed.
- Do not re-run those setup steps unless rebuilding the Supabase project from scratch.

Important:
- Supabase must have the correct email sender / SMTP settings configured if you want confirmation emails to come from your custom noreply address.
