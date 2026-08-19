SkinQuest v14.1.2

UPDATE AN EXISTING v14.1.1 PROJECT
1. Run NO SQL. This release has no database changes.
2. No Edge Function redeploy is needed.
3. Copy/replace the public site files with this version.
4. Hard-refresh the site, sign in, and test Surveys and Admin.

FOR A BRAND-NEW EMPTY SUPABASE PROJECT
- Use skinquest_full_setup_v14_1_2.sql once.
- Set CPX_APP_ID and CPX_SECURE_HASH_SECRET in Supabase Edge Function secrets.
- Deploy supabase/functions/survey-feed/index.ts.

v14.1.2 UPDATE
- Balances the CPX provider card so availability, guidance, and the action button each have clear breathing room.
- Rebuilds Operating overview as six separate KPI cards instead of concatenated inline text.
- Rebuilds Public system status as readable component cards with aligned status controls.
- Lets every panel inside the admin control room collapse to its title.
- Remembers collapsed admin sections in the current browser.
- No SQL or Edge Function changes.
