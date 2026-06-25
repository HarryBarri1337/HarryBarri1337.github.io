SkinQuest v10.0

Changes:
- Full-page background image style using site-background.png.
- More visible reward-page warning if the user has not saved a Steam trade URL.
- Redeem errors for missing trade links now show a direct modal instead of feeling like a random redirect.
- Level system changed to 1 level per 1,000 earned coins.
- Each new level awards +50 bonus coins through the new Supabase RPC claim_level_rewards().
- Cache bumped to styles.css?v=100 and app.js?v=100.

Supabase:
Run skinquest_v10_supabase_patch.sql once in Supabase SQL Editor.

Assets:
The zip does not include your assets/ folder. Keep your existing assets folder.
This version includes a root-level site-background.png used by the page background.
