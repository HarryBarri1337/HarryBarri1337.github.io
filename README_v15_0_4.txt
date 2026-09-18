SkinQuest v15.0.4
=================

Release focus
- Customer-facing dashboard, navigation, Help/How it works and reward-card polish.
- Finance & Funding form validation/normalization fixes.
- Trustpilot completed-order BCC integration from v15.0.3 is preserved.
- TimeWall callback path reviewed; failed-credit cases should be diagnosed from the failed postback response / Edge Function logs before changing accounting logic.

Customer UI
- Main navigation uses larger, better-spaced labels and no longer includes Help.
- Dashboard stat cards are more compact and centered; the extra text below Level is removed.
- Coin history is positioned below Achievements.
- How it works cards use more balanced copy and consistent sizing.
- Reward cards use less empty space and the whole card now has a clearer hover/click affordance.

Admin / Finance
- Finance type/category inputs are normalized so invalid backend combinations are not selectable accidentally.
- Provider is only enabled for provider income.
- Order ID is only enabled for item-purchase expenses.

Trustpilot
- Completed customer orders BCC the configured Trustpilot Automatic Feedback Service invite address.
- Grouped deliveries trigger the Trustpilot BCC only after the complete delivery is completed.
- Pending, trade-lock, ready-to-trade and admin-only emails do not trigger Trustpilot invitations.

SQL
- Existing installation upgrade: skinquest_upgrade_existing_to_v15_0_4.sql
- Fresh installation full setup: skinquest_full_setup_v15_0_4.sql
- v15.0.4 requires no database schema or data migration; the upgrade file is intentionally a documented no-op.

Deploy
1. Back up the current website deployment.
2. Upload the v15.0.4 website files, including skinquest-v154.css.
3. Deploy the included Supabase Edge Functions if the live project does not already contain the Trustpilot-modified reward-order-status-notify function.
4. Existing databases do not need SQL changes for v15.0.4.
5. Hard refresh once after deployment so all ?v=1504 assets and the v1504 PWA cache are used.

Release validation
- See RELEASE_CHECKS_v15_0_4.txt.
