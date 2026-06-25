SkinQuest v9.6

Fixes:
- Redeem no longer instantly redirects to Dashboard when Steam trade URL is missing/invalid.
- User now sees a real modal explaining what is missing.
- Dashboard Steam trade URL saving is hardened with a Supabase RPC.
- Better modal/toast styling with dark background, blur, and transitions.
- Cache bumped to app.js/styles.css?v=96.

Supabase:
Run skinquest_v9_6_supabase_patch.sql if normal users cannot save Steam trade URLs or redeem keeps saying the trade URL is missing.

Assets:
No assets folder included. Keep your own assets/ folder on GitHub.
