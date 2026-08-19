SkinQuest v14.0.4

UPDATE AN EXISTING v14.0.3 PROJECT
1. Run NO SQL. This release has no database changes.
2. Rotate the CPX secure-hash secret if it has ever been pasted into chat, source code, or another public place.
3. Set the CPX values as Supabase Edge Function secrets (never put the secret in app.js or HTML):

   supabase secrets set CPX_APP_ID=33831 CPX_SECURE_HASH_SECRET="YOUR_NEW_ROTATED_SECRET"

4. Deploy the updated authenticated Edge Function:

   supabase functions deploy survey-feed

5. Copy/replace the public site files with this version.
6. Sign in, open Surveys, and confirm the embedded CPX list and the "Open CPX in a new tab" fallback both work.

FOR A BRAND-NEW EMPTY SUPABASE PROJECT
- Use skinquest_full_setup_v14_0_4.sql once.
- Then configure the two CPX secrets and deploy survey-feed as described above.

v14.0.4 PATCH
- Added CPX Research's official full-content Script Tag widget to the Surveys page
- Loads exactly https://cdn.cpx-research.com/assets/js/script_tag_v2.0.js after a signed session is ready
- Uses CPX design 1, best-money ordering, a seven-survey limit, and iframe isolation
- Generates md5(ext_user_id + "-" + secret) only inside the survey-feed Edge Function
- Sends no email address or username in the CPX widget configuration
- Keeps a securely signed new-tab offerwall as a fallback
- Removes BitLabs data from survey-feed and keeps BitLabs/Lootably off the Surveys page
- No database changes
