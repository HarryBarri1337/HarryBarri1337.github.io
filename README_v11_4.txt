SkinQuest v11.4

Focus:
- Footer version label added across all pages.
- Background image moved to assets/interface/site-background.png.
- Navigation now shows level progress for signed-in users.
- Admin roles are split into admin and owner.
- Regular admins can review redeem requests and support requests.
- Owners can also adjust coins, manage reward listings/stock, and manage admin roles.
- Admin support inbox added for messages from the support widget.
- SQL updated with get_admin_role(), is_owner(), owner_set_admin_role(), owner-only reward management, and owner-only coin adjustments.

Setup notes:
1. Run skinquest_full_setup_v11.sql in Supabase if your database is not updated yet.
2. Add your own account as owner after signup:
   insert into public.admin_users (user_id, role)
   values ('YOUR-USER-ID-HERE', 'owner')
   on conflict (user_id) do update set role = excluded.role;
3. Add regular helpers as admins through the v11.4 Admin roles panel, or with SQL:
   insert into public.admin_users (user_id, role)
   values ('THEIR-USER-ID-HERE', 'admin')
   on conflict (user_id) do update set role = excluded.role;
4. Put your background at assets/interface/site-background.png.
5. Put your coin logo at assets/interface/coin_logo.png.
6. Put reward images under assets/rewards/weapons/ and assets/rewards/cases/.
