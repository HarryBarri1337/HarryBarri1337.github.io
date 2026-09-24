SkinQuest v15.1.0
=================

What's new
- Deliveries shows a clear next step for both single orders and shared Steam offers. The Completed action appears after Trade sent; mixed shared orders are handled individually until aligned.
- Every delivery and order drawer has a copyable Steam message containing its order reference. The same customer’s ungrouped orders remain separate actions.
- Giveaways has a customer tab, empty state, prize cards, end dates and entry counts. An admin can create several giveaways, choose an active catalog reward and change the default eight-day end time.
- Users explicitly enter each giveaway after a verified survey reward received after that giveaway opened. One reward can unlock several giveaways already open. One entry per account and giveaway is enforced in SQL.
- Admins can cancel a giveaway or draw after the end time. The draw filters out entries whose qualifying survey rewards were reversed, records the winner and keeps the result in the audit log. Winner contact and Steam trade URL appear privately to admins. Admins can copy a Steam giveaway message and record accepted manual delivery. Prize delivery does not deduct coins or stock automatically.
- TimeWall no longer appears connected based on a hardcoded fallback placement URL. Earning statistics includes a connection check for launcher configuration and received verified credits.

Existing-site deployment, in this order
1. Back up the site and Supabase database.
2. Run skinquest_upgrade_existing_to_v15_1_0.sql in Supabase SQL Editor. This expects v15.0.5 (including its finance upgrade) to be present. Run the new migration before uploading the new pages.
3. Deploy the updated website files, .htaccess and supabase/functions/survey-feed/index.ts. The existing timewall-postback function must also remain deployed with verify_jwt=false as specified by supabase/config.toml. Do not deploy the full_setup SQL to an existing database.
4. In Supabase Edge Function secrets, set TIMEWALL_IFRAME_URL_TEMPLATE to the real surveys placement URL, with its own oid and uid={user_id}. The launcher requires TIMEWALL_SECRET_KEY and an integer TIMEWALL_COINS_PER_USD (1–100000) as well. The old URL embedded in code is no longer a fallback. TIMEWALL_EARN_URL_TEMPLATE and TIMEWALL_EARN_SECRET_KEY are separate, optional settings for a different Earn placement.
5. In the TimeWall publisher dashboard, inspect the surveys placement and postback URL. The current callback expects GET /functions/v1/timewall-postback?placement=surveys with userid, txid, raw revenue, hash and type query values. The code expects a SHA-256 hash of userid + raw revenue text + survey secret. Ensure the dashboard maps its actual postback variables to these names and that the configured URL responds successfully. Do not paste secrets into an email or support ticket.
6. Open Admin > Earning statistics > TimeWall connection. A configured wall is only the first check; compare a real provider test completion with a new verified event and the customer's Coin history. Test a duplicate callback and a reversal from the provider dashboard before advertising TimeWall as reliably crediting.
7. Open Admin > Deliveries and check one prepared order, one orderable order with its actual Steam unlock time, a shared offer, and the accepted-offer Completed step. Open Admin > Giveaways, create a test giveaway, verify the customer can enter only after a credited survey reward, and draw it after its end. Do not use fake survey completions on production accounts.

Fresh setup
- Use skinquest_full_setup_v15_1_0.sql only for a new database, then deploy the Edge Functions and site files.

Rules and limits
- Eligibility means one positive, provider-verified survey reward in offerwall_events after the giveaway starts and before it ends. CPX may reward a screen-out; existing callback records do not prove that the whole questionnaire was finished. TimeWall Earn tasks are excluded.
- A reversed reward removes eligibility unless another qualifying reward remains. Entries stay recorded; the draw checks again. The public card explains the invalid state.
- The admin draw is final and randomly chooses from valid entered accounts. There is no automatic prize fulfilment; contact and trade the item manually after checking the winner's account.
- The admin TimeWall check sees local configuration and callback records, not the live publisher dashboard. No real TimeWall account settings, secret or live postback were available in this archive, so live crediting cannot be certified from the zip alone.
