SkinQuest v11.5

Focus: user flow, reward usefulness, admin workflow, support context, and changelog polish.

Important:
- This zip intentionally does NOT include the assets folder.
- Keep your existing assets locally:
  assets/interface/site-background.png
  assets/interface/coin_logo.png
  assets/rewards/weapons/...
  assets/rewards/cases/...

Files:
- skinquest_full_setup_v11_5.sql = full setup for a fresh Supabase project
- skinquest_upgrade_v11_5_from_v11_4.sql = only the SQL changes needed after v11.4

Main changes:
- Account dropdown in navigation with wallet, level and quick links
- First-time dashboard get-started panel
- Rewards: affordable/in-stock/need-more-coins filter
- Rewards: smarter CTAs like Need X more coins, Earn more coins, Add trade URL
- Better empty states for reward history and coin history
- Admin: system status cards
- Admin: copy/open trade URL, copy user ID/email and copy user update messages
- Support requests now capture page, browser/user agent, account email, and browser language when possible
- Changelog page linked from footer version
- Cache bumped to v=115

SQL:
If you already ran v11.4, run only:
skinquest_upgrade_v11_5_from_v11_4.sql

If you are setting up from scratch, run:
skinquest_full_setup_v11_5.sql
