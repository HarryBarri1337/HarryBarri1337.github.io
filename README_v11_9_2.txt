SkinQuest v11.9.2

Steam trust-domain hotfix for the v11.9.x Settings + Steam Connect release.

What changed in v11.9.2:
- Added steam-callback.html on skinquestcs.com.
- Steam can now return to a SkinQuest domain first, so the Steam login screen can show skinquestcs.com instead of the Supabase functions domain.
- The bridge page immediately forwards Steam's verified OpenID response to the existing Supabase steam-auth-callback function.
- No new database changes are required from v11.9.1.

Important:
- The website files alone are not enough to change the domain shown inside Steam.
- steam-auth-start must also be redeployed with the v11.9.2 version from STEAM_CONNECT_SETUP_v11_9_2.txt so its realm/return_to point to skinquestcs.com/steam-callback.html.

Release contents:
- Static frontend files.
- Full setup SQL: skinquest_full_setup_v11_9_2.sql
- Upgrade SQL: skinquest_upgrade_v11_9_2_from_v11_9_1.sql
- Setup notes.

Excluded on purpose:
- assets folder
- .github folder
- supabase folder
- old README files
