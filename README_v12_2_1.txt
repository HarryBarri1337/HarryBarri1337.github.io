SkinQuest v12.2.1

Release focus (small frontend patch, no database changes):
- Favicon (browser tab icon) is now transparent instead of a solid dark square.
- Fixed the goal star on dashboard "Goal rewards" cards overflowing outside the card when the reward name was long (missing flex min-width on the title).
- Version references updated to v12.2.1.
- Cache-busting updated to styles.css?v=1221 and app.js?v=1221.

Assets:
- Not included in this package.
- Keep your existing assets/interface files on the server.
- assets/icons/favicon-16.png and favicon-32.png were regenerated (now transparent) - re-upload those two files. The other icons in assets/icons/ are unchanged from v12.2.0.

Excluded from package:
- .git
- .github
- supabase

SQL:
- No schema changes in this release. No upgrade SQL file is included.
- If you have not already run skinquest_upgrade_v12_2_0_from_v12_1_2.sql (or the full setup) on your Supabase project, do that first - v12.2.1 has no SQL of its own.

Completed setup notes:
- Support notification setup is already completed.
- Steam auth setup is already completed.
- Do not re-run those setup steps unless rebuilding the Supabase project from scratch.

Important:
- Supabase must have the correct email sender / SMTP settings configured if you want confirmation emails to come from your custom noreply address.
