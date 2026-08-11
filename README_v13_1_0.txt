SkinQuest v13.1.0
=================

What changed
- BitLabs is active as a second survey provider with a signed-in offerwall.
- A dedicated BitLabs callback verifies the provider HMAC before applying coins.
- BitLabs callback transaction IDs are idempotent; positive and negative reconciliation events are supported.
- Account deletion can also delete the matching BitLabs publisher user.
- Redemption refunds restore coins but never add XP or trigger the reward-gain animation.
- The home page now has a clear Install SkinQuest shortcut.
- The install page uses recognizable Apple, Android, and desktop icons.
- Header, navigation, cards, forms, surveys, rewards, install, modals, and support UI received a final mobile layout pass.

Database files — choose one
1. skinquest_upgrade_existing_to_v13_1_0.sql
   Run this once on the CURRENT v13.0.0 SkinQuest project. It is safe to rerun.

2. skinquest_full_setup_v13_1_0.sql
   Use only for a completely new Supabase project. Never run this on production.

Existing-project deployment order
1. Back up the production database.
2. Run skinquest_upgrade_existing_to_v13_1_0.sql in Supabase SQL Editor.
3. In Supabase Edge Function secrets, confirm these BitLabs values exist:
   BITLABS_API_TOKEN       = BitLabs App/API Token
   BITLABS_APP_SECRET      = BitLabs Secret Key
   BITLABS_S2S_TOKEN       = BitLabs Server-to-Server Key

   Do not paste any of those values into HTML or app.js.
4. Deploy these updated/new Edge Functions:
   survey-feed             JWT verification ON
   bitlabs-postback        JWT verification OFF
   delete-account          JWT verification ON
5. Upload all website files from this package, including app.js, styles.css,
   install.html, earn.html, sw.js, and the assets folder.
6. Purge the host/CDN cache and reopen any installed SkinQuest PWA.

BitLabs dashboard setup
1. Currency:
   - Set the currency name to SkinQuest Coins (or Coins).
   - Set the currency factor to your intended coins per USD after your user
     revenue share. The VAL callback and survey value use this configured factor.
   - Do not guess the factor: choose it to match SkinQuest's payout economy.

2. Reward callback:
   - Method: GET
   - Endpoint:
     https://ubvkupqgigfxehprsoit.supabase.co/functions/v1/bitlabs-postback
   - Use the BitLabs callback editor/parameter picker to append these fields:
     uid = USER:UID
     tx  = TX
     val = CURRENCY:VALUE (the SkinQuest coin amount)
     raw = CURRENCY:USD
     type = TYPE / ACTIVITY:TYPE
     ref = REF (when offered by the callback editor)
   - Keep tx as BitLabs' unique transaction ID.
   - BitLabs automatically appends hash. Do not add a custom hash value.
   - Leave “Send $0 Rewarded Callbacks” disabled for this endpoint.
   - Save and use the BitLabs callback test before production traffic.

3. Offerwall:
   - No extra browser token is required. survey-feed builds the signed-in BitLabs
     wall from BITLABS_API_TOKEN and the authenticated SkinQuest user ID.

4. Optional individual survey cards:
   - Ask the BitLabs account manager to activate backend Survey API access and
     enable forwarding client_ip/client_useragent for this placement.
   - Only after they confirm it, add this Edge Function secret:
     BITLABS_BACKEND_API_ENABLED=true
   - Until then, BitLabs still works through its normal offerwall button.

Important behavior
- Refund: wallet balance returns; XP does not increase; no earning popup appears.
- BitLabs completion: positive VAL adds coins once.
- BitLabs reconciliation: negative VAL removes coins once. If the balance is too
  low, the balance stops at zero and the account is marked under review.
- Repeated callbacks with the same TX return success without changing balance.
- delete-account forwards deletion to BitLabs when BITLABS_S2S_TOKEN is set.

Verification checklist
- Open the home page on a phone and confirm the Install SkinQuest shortcut is visible.
- Open the mobile menu and confirm every navigation item is reachable and tappable.
- Check /install on iPhone/Android width and confirm the three platform icons render.
- Sign in, open /surveys, and confirm both CPX and BitLabs buttons open with the same user ID.
- Send the same positive BitLabs callback test twice; coins increase only once.
- Send a negative reconciliation with a new TX; coins decrease only once.
- Refund a test reward; coins return, XP remains unchanged, and no gain animation appears.
- Delete a test account only after all reward requests are resolved.

Operational notes
- The BitLabs Server-to-Server key is required for provider-side account deletion,
  even though it is not used for offerwall launch or reward callback hashing.
- Review final currency factor and legal controller/business details before launch.
