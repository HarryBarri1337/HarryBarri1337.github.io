SkinQuest v15.0.2

FROM YOUR LIVE v15.0.1:
1. Upload the new website files, including skinquest-v152.css and sw.js.
   Upload assets/CSS/JS before HTML, or publish atomically.
2. Reload the page (Ctrl+F5 on desktop) and reopen an installed PWA.
3. Check Dashboard, Rewards, Surveys and Earn.

No SQL, Edge Functions, secrets or Cron changes for this update.
The v15.0.2 upgrade SQL contains comments only. Do not run full setup.
Full setup is retained only for a completely new installation.

Changes:
- Dashboard is back in the main navigation.
- Navigation and page content share their outer width.
- Removed First rewards/Within my balance/Cases/AK-47 quick buttons and
  the search instruction paragraph. Search and filtering still work.
- Counts say rewards, including when variants are grouped.
- Top CPX Research/TimeWall buttons open the secure account-bound provider
  wall directly in a new tab. Buttons are disabled until the URL is verified.
  Logout removes those signed links. Open-click tracking is retained.
- Surveys/Earn buttons have matching layout and spacing.
- Goal rewards is now Saved rewards: your starred items, not extra bonuses.
  Long titles, stars, coin amounts and progress bars stay inside their cards.

Sticker Slab protection and all v15.0.1 order/payment/database safeguards
remain unchanged. No saved stars, coins, orders or history are reset.

Local QA uses mocked provider and Supabase sessions, not real credits or
payments. Verify the provider sessions and PWA on your real devices as well.
