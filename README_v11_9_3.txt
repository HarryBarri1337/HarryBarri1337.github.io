SkinQuest v11.9.3

Steam auth release for the v11.9.x cleanup branch.

What changed:
- Steam can now be used from the login/sign-up modal.
- Existing logged-in users can still connect Steam from Settings.
- Connected users can disconnect Steam from Settings.
- Settings displays Steam-only accounts cleaner instead of showing the generated backend email.
- Steam trust-domain flow still uses skinquestcs.com/steam-callback.html so Steam shows skinquestcs.com.

Required Supabase work:
- Run skinquest_upgrade_v11_9_3_from_v11_9_2.sql.
- Update/redeploy steam-auth-start.
- Update/redeploy steam-auth-callback.
- Create/deploy steam-disconnect.
- Use STEAM_AUTH_SETUP_v11_9_3.txt for the function code.

Release contents:
- Website files
- steam-callback.html
- Full setup SQL: skinquest_full_setup_v11_9_3.sql
- Upgrade SQL: skinquest_upgrade_v11_9_3_from_v11_9_2.sql
- Steam setup notes: STEAM_AUTH_SETUP_v11_9_3.txt
- Support setup notes

Not included:
- assets folder
- .github folder
- supabase folder
