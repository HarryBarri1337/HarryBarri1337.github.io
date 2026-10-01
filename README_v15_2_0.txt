SkinQuest v15.2.0
=================
Based on the live v15.1.1 release.

DEPLOYING OVER THE LIVE v15.1.1 SITE
1. Run skinquest_upgrade_existing_to_v15_2_0.sql in Supabase SQL Editor.
   Run this NEW upgrade before uploading the website files. It is transactional
   and repeatable. Do not use the full-setup file on your existing database.
2. Copy the contents of this folder into the website repository root and push
   to main, or upload the website files to /public_html/ using the usual method.
   Include ALL HTML, JavaScript and CSS, plus sw.js. In particular include
   skinquest-deliveries.js and skinquest-v1520.css.
3. Refresh Admin > Deliveries and Admin > Finance & funding.
   The footer and admin sidebar should show v15.2.0.

No new Edge Function deployment or secrets are required for this release.
Keep the already-deployed reward-order-status-notify function: it sends the
normal customer updates after a delivery step is saved.

FRESH DATABASE ONLY
Use skinquest_full_setup_v15_2_0.sql. It includes the previous complete setup
and the SAME v15.2.0 upgrade, then deploy the existing functions/site as usual.
The older v15.1.0 upgrade is retained only for installations predating v15.1.0.

PERSONAL PURCHASES / REIMBURSEMENTS
- Type: Expense; category: Reward / skin purchase.
- Payment status: Paid personally - awaiting reimbursement.
- Enter who paid (for example Harry), the purchase date and a reference.
- Choose EUR and enter 10.00 for a EUR 10 purchase. Enter the actual SEK/EUR
  rate from your purchase or bank receipt. Company totals stay in SEK; the
  original currency, amount and conversion rate remain attached to the record.
- The cost appears immediately in Total costs and Unpaid costs. SkinQuest owes
  the named payer; Company cash does not decrease before reimbursement.
- After SkinQuest actually pays you, press Mark reimbursed. The SAME record
  becomes paid, unpaid costs decrease, and company cash decreases once.
- Unpaid invoice - SkinQuest will pay also records a cost before company cash
  has moved. Income and funding continue to represent money actually received.
- Existing paid SEK records remain paid. Historical unconverted non-SEK
  entries remain excluded from SEK totals until you explicitly replace them.
- Owners manage all records; admins manage records they created. Reimbursement
  actions record a payment you made; the site does not initiate a bank transfer.

FASTER DELIVERIES
- Search the queue by customer, email, order number or reward. The Ready now,
  To purchase, Trade locked, Awaiting acceptance and Link review buttons filter
  customers. Opening a customer always shows ALL their active orders.
- Ready items are selected first. Use the quick selection buttons or checkboxes.
  A shared delivery's active items are selected together, up to 100 per action.
- The item checklist totals repeated skins/cases (for example 7 x Kilowatt Case).
  Copy ONE Steam message and open the saved Steam trade link.
- Make shared delivery groups the selection. Separate orders reverses grouping
  before sending. Select an existing unsent delivery plus new individual orders
  and use Make shared delivery to combine them.
- If you send several selected ungrouped orders in one actual Steam offer, the
  I sent the Steam offer action groups and marks them sent in one transaction.
- For items needing purchase, enter Steam's actual future unlock time and press
  Purchased / trade locked. Only items awaiting purchase change; ready items and
  existing locks remain at their current stage.
- Select Sent offers and mark Customer accepted - complete after acceptance.
  Once a customer has no active orders left, the workspace moves to the next
  available customer. Next customer also lets you move through the queue manually.
- Changed links require a Steam-account review. Future locks cannot be bypassed;
  unsent and sent items must be handled separately when recording an offer.

The upgrade replaces the deliveries query with the real steam_trade_url column,
including the compatibility RPC used by older pages. It does not add or rely on
the misspelled steam_trade_aurl column reported by the live database.
