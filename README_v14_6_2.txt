SkinQuest v14.6.2 — TimeWall surveys alongside existing CPX

Existing v14.6.1 deployment:
1. Backup Supabase. Run ONLY skinquest_upgrade_existing_to_v14_6_2.sql.
   Never run skinquest_full_setup_v14_6_2.sql against the existing site.
   If you already ran the earlier v14.6.2 delta BEFORE the hold/chargeback
   correction, run this updated delta once more; it is safe to apply again.
2. Deploy the NEW Edge Function timewall-postback from
   supabase/functions/timewall-postback/index.ts. Disable Verify JWT for this
   provider callback only. Its hash and SQL restrictions are checked in code.
3. In Edge Functions > Secrets set TIMEWALL_SECRET_KEY to the TimeWall
   placement's publisher Secret Key. Do not send the value to anybody.
   Set TIMEWALL_COINS_PER_USD=1000 ONLY if you confirm the placement uses
   1000 SkinQuest Coins per $1. This must match TimeWall's conversion rate.
4. In TimeWall create Offerwall (iFrame), Surveys ONLY, Auto Redeem. Website URL
   https://skinquestcs.com. Set the Postback URL to:
   https://ubvkupqgigfxehprsoit.supabase.co/functions/v1/timewall-postback?userid={userID}&txid={transactionID}&revenue={revenue}&hash={hash}&type={type}&original_txid={original_txid}
   Select TimeWall's exact macros from its Insert Macro tool. The value above
   must be confirmed against its current dashboard; never add the publisher
   Secret Key to the URL. Whitelist the CURRENT callback IPs shown by TimeWall
   in your own network gateway only if you can trust the gateway's IP header.
5. Deploy the UPDATED survey-feed Edge Function. When TimeWall creates your
   placement, obtain its iframe embed URL and verify that it accepts the
   SkinQuest user UUID as the user ID. Set TIMEWALL_IFRAME_URL_TEMPLATE to the
   real HTTPS URL with exactly one {user_id} placeholder in that user-ID
   parameter. The survey-feed rejects other hosts and generic URLs.
   Until this value exists, TimeWall stays HIDDEN and CPX remains usable.
6. Upload the website files. Do not make TimeWall public until a test postback
   verifies a real test account, the credited amount, event ID, duplicate
   delivery handling, CPX still works, and the user's ability to access the
   iframe. TimeWall's own dashboard says test postbacks need support; never
   create synthetic signed credits in production.

Risk limits: <=5000 coins per TimeWall postback, <=15000 completed TimeWall
coins per user in any rolling 24 hours. Credits share the existing offerwall
ledger and coin history with CPX but are labelled provider='timewall'. Review
TimeWall's real dollars and transactions PER USER against SkinQuest's TimeWall
coin ledger BEFORE buying/trading an item on any account that used TimeWall.
Signed hold/hold_cancelled callbacks never award coins. Signed chargebacks
reverse the ORIGINAL transaction and may flag an overdrawn account for manual
review. The currently documented TimeWall hash does NOT cover transaction ID. Its
publisher reports offer detection, not cryptographic fraud prevention; do not
offer automatic skin delivery. Fraud/chargebacks can still cost
money and require manual intervention. Supabase/TimeWall integration has NOT
been exercised against this live account.

Rewards page is deliberately UNCHANGED in this release.
