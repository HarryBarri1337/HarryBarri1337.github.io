SkinQuest v12.2.8

What this release fixes
- The Steam Trade URL button is bound immediately when the Settings page starts.
- The button changes to "Saving..." before any Supabase request begins.
- Inline status text now shows saving, success, validation, timeout, and database errors.
- The save request has explicit timeouts so the button cannot sit silently forever.
- Trade URL validation accepts normal Steam trade links with partner and token in either order.

SQL files in this package
1. skinquest_upgrade_existing_to_v12_2_8.sql
   Run this on the EXISTING SkinQuest Supabase project.
2. skinquest_full_setup_v12_2_8.sql
   Use this only for a completely NEW Supabase project.

There are no obsolete upgrade SQL files in this package. The full setup contains the same v12.2.8 trade URL function, grants, and RLS policy as the existing-project upgrade.

Deployment order
1. In Supabase SQL Editor, run skinquest_upgrade_existing_to_v12_2_8.sql.
2. Upload the web files and replace the old files in public_html.
3. Keep the existing assets folder on the server.
4. Hard refresh the Settings page (Ctrl+F5).
5. Test with a full Steam trade URL and confirm it remains after reloading.

Verification performed
- JavaScript syntax check.
- HTML references for app.js/styles.css version 1228.
- Trade form IDs and event binding checked.
- Full SQL and upgrade SQL trade function compared for parity.
- Obsolete v12.2.4/v12.2.7 SQL and README files removed.
- Service worker cache bumped to v1228.

Live Supabase behavior still requires the final signed-in production test after deployment.
