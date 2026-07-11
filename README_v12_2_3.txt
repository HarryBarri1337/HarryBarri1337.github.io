SkinQuest v12.2.3

Release focus (frontend only, no database changes):
- Added the Google Analytics tag (gtag.js, measurement ID G-DFRR03C4BP) to the <head> of every page.
- Version references updated to v12.2.3. Cache-busting updated to styles.css?v=1223 and app.js?v=1223 (also refreshes the service worker's precache list).

Assets:
- No asset changes in this release.

Excluded from package:
- .git
- .github
- supabase

SQL:
- No schema changes in this release. No upgrade SQL file is included.
- Most recent schema is still skinquest_upgrade_v12_2_0_from_v12_1_2.sql / skinquest_full_setup_v12_2_0.sql.

Completed setup notes:
- Support notification setup is already completed.
- Steam auth setup is already completed.
- Do not re-run those setup steps unless rebuilding the Supabase project from scratch.

Important:
- Supabase must have the correct email sender / SMTP settings configured if you want confirmation emails to come from your custom noreply address.
