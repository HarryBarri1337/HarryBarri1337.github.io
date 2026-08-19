SkinQuest v14.1.0

UPDATE AN EXISTING v14.0.4 PROJECT
1. Run NO SQL. This release has no database changes.
2. No Edge Function redeploy is needed when survey-feed from v14.0.4 is already live.
3. Copy/replace the public site files with this version.
4. Hard-refresh the site, sign in, and test Surveys and Rewards.

FOR A BRAND-NEW EMPTY SUPABASE PROJECT
- Use skinquest_full_setup_v14_1_0.sql once.
- Set CPX_APP_ID and CPX_SECURE_HASH_SECRET in Supabase Edge Function secrets.
- Deploy supabase/functions/survey-feed/index.ts.

v14.1.0 UPDATE
- Rebuilt Surveys with the selected split layout: CPX Research summary on the left and live offers on the right.
- Keeps the official signed CPX widget and iframe isolation from v14.0.4.
- Shows six offers at a time for a balanced grid.
- The signed fallback button now reads "Open CPX Research" and still opens CPX in a new tab.
- Separated reward-card progress and remaining-coin values for narrow screens.
- No SQL or Edge Function changes.
