SkinQuest v11.9

Focus: settings cleanup, admin support inbox cleanup, and small site polish.

Included changes:
- Rebuilt Settings into clean Account, Notifications, Theme, and Account safety sections.
- Removed Reward browsing preferences from Settings.
- Removed Quick actions from Settings.
- Removed the Redeem setup/readiness block from Settings; setup guidance stays at the top of Dashboard and hides when completed.
- Added clearer Connected Logins cards for Email, Steam, and Google.
- Added Theme section with Nuke Theme current and Mirage/Ancient marked as future.
- Admin support inbox now hides resolved support requests from the main list.
- Shortened the How it works page copy so it is less text-heavy.
- Fixed a duplicated CSS background line in the support floating button and added small settings polish.

Files:
- skinquest_full_setup_v11_9.sql
- skinquest_upgrade_v11_9_from_v11_8_3.sql
- SUPPORT_NOTIFY_SETUP_v11_9.txt
- supabase/functions/support-notify/index.ts

SQL note:
No database change is required if v11.8.3 SQL was already applied. The upgrade SQL is intentionally a no-op marker.

Important setup note:
Support email notifications still depend on the already-created Supabase Edge Function, Resend secrets, and database webhook.

Assets are not included. Keep using the existing assets folder.
