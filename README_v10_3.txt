SkinQuest v10.3

Focus: cleaner wallet visuals, faster page transitions, dashboard coin-logo alignment, and small stability polish before v11 auth work.

Changes:
- Removed the large fake coin art from the home wallet card.
- Removed the WALLET label on the home wallet card.
- Reworked the home wallet card into a cleaner account snapshot.
- Changed Dashboard "Available coins" to "Wallet".
- Added the project coin logo beside the Dashboard wallet balance, centered.
- Changed the full-screen movie-style loader into a small top loading bar.
- Removed the artificial loader delay and hides it earlier during boot.
- Added console warning if level reward RPC fails instead of silently hiding every error.
- Bumped CSS/JS cache links to v=103.

Level system note:
- The frontend calculates level from confirmed positive coin credits, excluding level reward credits.
- The +50 coin level bonus requires the Supabase patch function claim_level_rewards() from skinquest_v10_supabase_patch.sql.
- Bonus claiming currently happens when the dashboard opens. If the SQL patch is not run, the visual level can still show, but the 50-coin bonus will not be awarded.
