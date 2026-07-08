SkinQuest v12.1.0

Release focus
- Release version after v12.0.2 focused on fixing the deployed background and adding notification subscriber visibility.
- Keeps the main SkinQuest interface colors consistent across map themes.
- Makes map themes slightly more visible without turning the whole UI into that map color.
- Reduces AI-looking heavy typography by keeping bold mainly for headings, buttons, badges, and key stats.
- Makes the header logo slightly larger while keeping the navbar balanced.
- Moves Themes above Notifications in Settings.
- Adds admin-only Supabase views for seeing notification subscriber emails by category.

What changed
- Version references updated to v12.1.0.
- Cache-busting updated to styles.css?v=1210 and app.js?v=1210.
- Added lighter typography polish so regular text, descriptions, and small copy feel less over-bold.
- Increased the brand logo size a little, with responsive sizes for tablet and mobile.
- Strengthened theme mood slightly through background glow, subtle header/page accents, and theme cards.
- Kept the default SkinQuest interface colors stable instead of recoloring the whole interface per map.
- Moved the Theme settings panel above Notifications.
- Added extra navbar/profile stability CSS to reduce layout movement while auth refreshes.
- Fixed the background layer so map/site background images render above the body color but below the UI.
- Added admin-only SQL views for notification subscriber lists.
- Updated changelog with v12.1.0 notes.

Completed setup notes
The following setup work has already been completed in the live project and should not be re-run unless the Supabase project is rebuilt from scratch:
- Support notification setup
- Steam auth setup

SQL notes
- v12.1.0 adds admin-only views for notification subscriber visibility.
- Run skinquest_upgrade_v12_1_0_from_v12_0_2.sql on the live Supabase project.
- The full setup SQL file is included as the current full setup baseline.

Notification admin views
After running the upgrade SQL, owner/admin accounts can query these in Supabase SQL Editor:
- public.admin_notification_subscribers
- public.admin_notification_reward_update_emails
- public.admin_notification_offer_issue_emails
- public.admin_notification_product_update_emails

The views use auth.users.email as the real email source and only fall back to profiles.username if it looks like an email. Non-admin users get zero rows because the views are gated with public.is_admin().

Expected external assets
These files are expected to already exist in assets/interface/ and are not included in this release zip:
- skinquestlogo.png
- nuke-background.png
- train-background.png
- mirage-background.png
- dust2-background.png
- ancient-background.png

Not included in this release zip
- .git
- .github
- supabase
- assets
