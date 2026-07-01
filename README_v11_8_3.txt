SkinQuest v11.8.3

Focus: support widget makeover and real support-notification groundwork.

Included changes:
- Floating support button/panel makeover.
- Required reply email field in the support widget.
- Logged-in users get their account email prefilled.
- Guest users can submit support requests with a reply email after running the SQL upgrade.
- Support requests still save to Supabase support_requests/admin panel.
- support@skinquestcs.com added to the support widget and footer/contact areas.
- Supabase Edge Function added at supabase/functions/support-notify/index.ts for server-side email notifications.
- SQL upgrade updates support_requests RLS/grants for guest support submissions.

Files:
- skinquest_full_setup_v11_8_3.sql
- skinquest_upgrade_v11_8_3_from_v11_8_2.sql
- SUPPORT_NOTIFY_SETUP_v11_8_3.txt
- supabase/functions/support-notify/index.ts

Important setup note:
The website update and SQL upgrade are not enough by themselves to send email notifications.
To activate real support email notifications, deploy the Edge Function, set Supabase secrets, and create the Database Webhook described in SUPPORT_NOTIFY_SETUP_v11_8_3.txt.

Assets are not included. Keep using the existing assets folder.
