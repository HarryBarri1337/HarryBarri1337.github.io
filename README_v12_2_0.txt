SkinQuest v12.2.0

Release focus:
- Mobile layout fixes: the Rewards page status bar (result count + goal-star counter + clear filters) no longer crowds together on narrow phones, and dashboard goal reward cards stack vertically on narrow phones instead of squeezing the picture and text into one row.
- The installable app icon is now the SQ shield mark only (no "SkinQuest" wordmark), scaled to fill the icon like a normal app icon.
- Raised the goal rewards star limit from 5 to 6.
- Version references updated to v12.2.0.
- Cache-busting updated to styles.css?v=1220 and app.js?v=1220.

Assets:
- Not included in this package.
- Keep your existing assets/interface files on the server.
- assets/icons/ was updated in this release (new icon-only artwork) - re-upload the whole assets/icons/ folder.

New/updated files in this release:
- assets/icons/icon-192.png, icon-512.png, icon-maskable-192.png, icon-maskable-512.png, apple-touch-icon.png, favicon-32.png, favicon-16.png (regenerated, SQ mark only)
- manifest.json and sw.js unchanged in structure, just cache version bumped

Excluded from package:
- .git
- .github
- supabase

SQL:
- Full setup SQL is included (skinquest_full_setup_v12_2_0.sql).
- Upgrade SQL is included (skinquest_upgrade_v12_2_0_from_v12_1_2.sql).
- Schema change in v12.2.0: the favorite_rewards limit trigger now allows 6 stars instead of 5. No new tables.
- Run the upgrade SQL once on your existing Supabase project. It only contains what changed since v12.1.2.
- If you are upgrading from v12.1.1 or earlier, run skinquest_upgrade_v12_1_2's contents first (create the favorite_rewards table) before this one, or just run the full setup SQL instead.

Completed setup notes:
- Support notification setup is already completed.
- Steam auth setup is already completed.
- Do not re-run those setup steps unless rebuilding the Supabase project from scratch.

Important:
- Supabase must have the correct email sender / SMTP settings configured if you want confirmation emails to come from your custom noreply address.
