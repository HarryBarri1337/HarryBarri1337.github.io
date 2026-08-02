SkinQuest v12.2.7

Main fix
- Repaired saving and clearing Steam trade URLs.
- Added a required Supabase upgrade script for existing projects:
  skinquest_upgrade_v12_2_7_from_v12_2_6.sql
- The validator now accepts normal Steam links with partner/token parameters in either order.
- Added a restricted own-profile fallback if the secure RPC is temporarily unavailable.
- Improved error details instead of showing only a generic save failure.

Required deployment
1. Run skinquest_upgrade_v12_2_7_from_v12_2_6.sql once in Supabase SQL Editor.
2. Upload the website files and replace the old v12.2.6 files.
3. Keep the existing assets directory on the server.
4. Hard-refresh the site or clear the installed PWA cache.

Verification completed
- JavaScript syntax check passed.
- Internal clean URL routes checked.
- Authentication/profile creation flow reviewed.
- Trade URL save and redeem prerequisites reviewed.
- Rewards loading, favorites, level claims, notification settings, support form,
  Steam connect/disconnect, admin access, and service-worker registration reviewed statically.

Important
- Static verification confirms code wiring and database permissions in this package.
- Live Supabase/Steam/offerwall behavior still requires one signed-in production test after deployment.
