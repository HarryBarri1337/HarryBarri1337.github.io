SkinQuest v9.3

Changes:
- Fixed the rewards/admin page fade-out bug caused by the loader wrapper not closing before the page content.
- Rebuilt the UI into a cleaner marketplace-style layout with fewer glow/AI-template effects.
- Removed coin_logo.png from the site logo and loading screen. The header now uses a simple SQ brand mark.
- coin_logo.png is now used as the coin icon only, and coin icons are slightly larger.
- Account menu is simplified into a standard wallet chip + account dropdown.
- Rewards/admin loading is more tolerant if old points_cost/points_coins columns differ.
- Admin reward creation sends both points_coins and points_cost to avoid the old NOT NULL issue.
- Mobile layout improved for header, account dropdown, forms, reward cards and admin pages.

No new Supabase SQL is required if v9 SQL already ran.
Do not delete your assets folder. This zip does not include assets.
Required asset for coin display:
assets/interface/coin_logo.png
