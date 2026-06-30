SkinQuest v11.2

Focus: test-phase polish and stability before broader user testing.

Changes:
- Admin access now depends on Supabase admin_users via is_admin(); frontend email fallback is disabled.
- Initial nav auth state uses a neutral skeleton instead of flashing Sign in/Sign up while Supabase checks the session.
- Dashboard and Settings show a neutral checking state instead of flashing logged-out panels.
- Page loader visuals are removed.
- Support widget now has open/close animation and saves signed-in requests to support_requests.
- Dashboard trade URL form moved fully to Settings.
- Dashboard ready checklist removed; only a red redeem blocker appears if the account cannot redeem yet.
- Dashboard wallet amount is centered while the coin logo sits to the left.
- Rewards default sort is Price: high to low; out-of-stock rewards remain last.
- Redeem requests now have Show more, matching coin history.
- Mobile nav/icon alignment polish.

Important setup:
Run skinquest_full_setup_v11.sql in Supabase. Then add your admin user UUID to public.admin_users, otherwise admin.html will deny access.
