SkinQuest v14.5.3 — upgrade an existing v14.5.2 installation
================================================================

This release assumes v14.5.2 is already live.

WHAT CHANGED
- Promo codes can be searched by code/campaign, filtered by status, enabled,
  disabled, and deleted by the owner.
- Deleting a used promo preserves the redemption snapshot and awarded coins.
- Manual reward listings can be searched and deleted once no open order or
  reserved stock remains. Historic orders keep the original reward name and
  coin amount and are labelled "Deleted item".
- A listing can hold prepared stock and retain an order fallback. Prepared
  units are redeemed first; when they run out, the same listing becomes
  Available to order. Duplicate exact reward names/market names are blocked.
- Admin reward filters distinguish In stock now and Order items only, with
  stock-first, order-first, name, and price sorting.
- Native browser select menus were replaced with SkinQuest-styled menus across
  the site.

UPGRADE ORDER
1. Back up the Supabase database.
2. In SQL Editor run ONLY skinquest_upgrade_existing_to_v14_5_3.sql.
   Do not run the full setup on an existing database.
3. Upload/replace the website files from this archive.
4. Hard-refresh the site and test reward stock, promo enable/disable, and one
   safe deletion.

NO EDGE FUNCTION CHANGES ARE REQUIRED FOR v14.5.3.
Leave steam-market-sync, its Cron job, headers, secret, and schedule unchanged.

Fresh installations can use skinquest_full_setup_v14_5_3.sql.
FEVER CASE EXAMPLE
Search for the existing Fever Case listing in Admin > Rewards & stock, choose
Edit, set Prepared quantity to 5, and choose "Keep available to order". This is
one listing: the first five orders reserve your stock, then later orders use the
order workflow. Do not create a second Fever Case listing.

ORDER DELETION POLICY
Normal order rows cannot be deleted. They are financial/customer history. When
a manual catalog item is removed, completed/cancelled/refunded/rejected orders
remain visible with the original name and coin price. Open orders block catalog
deletion until they are completed or cancelled.

Local syntax and package checks are included; live database permissions and
workflows must still be verified in your Supabase project.
