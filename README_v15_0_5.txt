SkinQuest v15.0.5
=================

Release focus
- Keeps the release at v15.0.5 and refines Finance & Funding for the actual SkinQuest workflow.
- Preserves the dashboard-width and reward-detail fixes already made in v15.0.5.
- Preserves Trustpilot completed-order BCC integration and all earlier v15.0.x work.

Finance & Funding
- Currency is SEK for all new/edited finance records and all live cash totals.
- Finance tracks actual cash movements only. Payment state, expected income and expected cost fields were removed from the UI.
- Top cards show Money available, Income, Expenses and Owner funding.
- Money available = owner funding + actual income - actual expenses.
- Entry fields are Type, Category, Amount, Date, Reference / who bought it, external Order / invoice ID, and Note.
- Relevant categories include provider income, reward/skin purchase, hosting & software, marketing, fees and other.
- The external Order / invoice ID is the order number supplied by the store/service. Internal SkinQuest order linking remains hidden and is used only when Record cost is launched from an open reward order.
- Finance rows clearly show which admin created them.
- Owners can edit/delete any finance record. Regular admins can create income/expense records and can edit/delete only records they personally created. Owner funding remains owner-only. These permissions are enforced in SQL, not only hidden in the UI.
- Delete is a permanent finance-record deletion after an explicit confirmation. A deletion event with the deleted record summary remains in the admin audit log.
- Duplicate human references are allowed; Reference is no longer treated as a unique transaction key.
- Existing legacy EUR rows are preserved as EUR and excluded from SEK cash totals instead of silently inventing an exchange rate. Re-enter/edit them in SEK if needed.

Dashboard / reward detail preserved
- Top dashboard cards remain compact while lower dashboard panels use normal page width.
- Coin history remains directly below Achievements.
- Reward detail delivery information remains in the left rail below the artwork to avoid blank space.

SQL
- Existing installation: run skinquest_upgrade_existing_to_v15_0_5.sql. This is no longer a no-op because Finance permissions/schema/RPCs changed.
- Fresh installation: skinquest_full_setup_v15_0_5.sql contains the same finance model.

Deploy
1. Back up the website and Supabase database.
2. Run skinquest_upgrade_existing_to_v15_0_5.sql in Supabase SQL Editor.
3. Upload all v15.0.5 website/admin files.
4. Hard refresh once so the v1505 assets are reloaded.
5. Test Finance once as Owner and once as a normal Admin before using it for real records.
6. Verify an Admin cannot edit/delete an Owner-created or other-Admin-created record.

Release validation
- See RELEASE_CHECKS_v15_0_5.txt.
