SkinQuest v14.1.1

UPDATE AN EXISTING v14.1.0 PROJECT
1. Run NO SQL. This release has no database changes.
2. No Edge Function redeploy is needed.
3. Copy/replace the public site files with this version.
4. Hard-refresh the site, sign in, and test Surveys and Rewards.

FOR A BRAND-NEW EMPTY SUPABASE PROJECT
- Use skinquest_full_setup_v14_1_1.sql once.
- Set CPX_APP_ID and CPX_SECURE_HASH_SECRET in Supabase Edge Function secrets.
- Deploy supabase/functions/survey-feed/index.ts.

v14.1.1 UPDATE
- Gives the Surveys workspace more room and stacks the CPX summary above the offers before the split layout becomes cramped.
- Keeps the selected split layout on wide desktop screens with a wider content area and larger spacing.
- Replaces the browser-native Weapon, Condition, and Rarity lists with SkinQuest-styled dropdown menus.
- Removes the Goals only filter while keeping goal stars on reward cards.
- Restyles Reset filters as a proper aligned filter-bar action and disables it until a filter is active.
- No SQL or Edge Function changes.
