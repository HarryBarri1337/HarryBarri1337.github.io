SkinQuest v15.2.1
=================
Hotfix for the live v15.2.0 site.

DEPLOY ON YOUR EXISTING SITE
1. Run skinquest_upgrade_existing_to_v15_2_1.sql in Supabase SQL Editor.
   This is the current cumulative upgrade. It works over v15.1.x or v15.2.0
   and can safely be rerun. Do not run full setup on your existing database.
2. Upload the website files as usual, including admin.html, admin.js,
   skinquest-deliveries.js, skinquest-v1521.css and sw.js.
   If using the existing GitHub deployment, copy these files into the repository
   root and push main. Include the updated HTML for the v15.2.1 footer/cache.
3. Hard-refresh (Ctrl+F5). Check the version reads v15.2.1.
4. In Finance, save Expense > Reward / skin purchase > Paid personally -
   awaiting reimbursement. Enter the payer, purchase amount, currency and
   actual SEK exchange rate for foreign currency.

WHAT CHANGED
- Fixed sq_finance_entries_settlement_check on older live databases. The
  v15.2.0 upgrade added pending payment support but missed replacing this older
  constraint. The new SQL explicitly replaces it with the paid/pending rule.
- Existing finance records are preserved. Pending costs count as expenses
  immediately but only reduce company cash when paid or reimbursed.
- Every delivery order has a separate bordered card with spacing, a prominent
  order number, item name, coin cost, purchase source and order date.
- Selected cards display Selected and a gold edge. Shared deliveries have a
  gold outer border and a header explaining that their orders are selected as
  one offer. Separate orders stay in their own clearly labelled section.
- Bulk actions are labelled Actions for selected orders below the checklist.
  Shared selection and the v15.2.0 bulk fulfilment behavior remain available.

No Edge Function updates or new secrets are needed.

FRESH DATABASE ONLY
skinquest_full_setup_v15_2_1.sql includes the complete prior setup followed by
EXACTLY the same current cumulative upgrade as the existing-site file.
For installations older than v15.1.0, apply the retained v15.1.0 upgrade first.
