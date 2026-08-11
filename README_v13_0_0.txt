SkinQuest v13.0.0
=================

Release contents
- Rebuilt Surveys page with signed CPX links and provider-ready BitLabs/Lootably postbacks.
- Idempotent survey credits, reversals, and account review when a reversal exceeds the current balance.
- Order confirmation email to the user and detailed new-order email to the administrator.
- Password recovery, GDPR account deletion, data-copy requests, stronger signup, and accessible auth modal.
- Server-side support validation and rate limiting. Direct public database inserts are removed.
- Reward per-user limits, Steam URL allow-listing, one-time refunds, and the accidental 1-coin Galil listing disabled.
- Rejected/refunded rewards return coins as a positive coin adjustment; those returned coins count toward XP.
- Install page, QR code, app shortcuts, clean-route offline support, update-safe service worker, and pinned Supabase browser client.
- robots.txt, sitemap.xml, canonical and social metadata, noindex on private pages, updated Terms and Privacy Policy.

Database files — choose one
1. skinquest_upgrade_existing_to_v13_0_0.sql
   Run once on the CURRENT SkinQuest Supabase project.

2. skinquest_full_setup_v13_0_0.sql
   Use only for a completely new Supabase project. Do not run this on production.

Required deployment order
1. Back up the production database.
2. Run skinquest_upgrade_existing_to_v13_0_0.sql in Supabase SQL Editor.
3. Set Edge Function secrets:
   SUPABASE_URL
   SUPABASE_ANON_KEY
   SUPABASE_SERVICE_ROLE_KEY
   RESEND_API_KEY
   EMAIL_FROM             example: SkinQuest <orders@skinquestcs.com>
   ADMIN_REWARD_EMAIL     destination for new reward orders
   RATE_LIMIT_SECRET      long random value
   SURVEY_POSTBACK_SECRET long random value
   CPX_APP_ID             default is 33831
   CPX_SECURE_HASH_SECRET CPX app secret used for secure_hash
4. Deploy these Edge Functions without disabling JWT verification unless your provider postback cannot send a JWT:
   reward-order-notify
   delete-account
   support-submit
   survey-feed
   survey-postback
   Existing Steam and support-notify functions remain included.
5. The survey-postback endpoint authenticates provider calls with x-postback-secret or ?secret= and then calls the service-role-only database RPC. Configure each provider dashboard to pass provider, event_id, user_id, amount/coins, and status. Map CPX, BitLabs, and Lootably field names in the provider dashboard or adapt survey-postback/index.ts if their account uses different names.
6. For public provider postbacks, deploy survey-postback with JWT verification disabled and rely on the long SURVEY_POSTBACK_SECRET. Keep JWT verification enabled for every user-facing function.
7. Upload every website file, including .htaccess, robots.txt, sitemap.xml, install.html, sw.js, manifest.json, assets/vendor, and assets/interface/install-qr.svg.
8. Purge the host/CDN cache, then hard-refresh or close and reopen the installed PWA.

Provider activation
- CPX is the active provider. Set CPX_SECURE_HASH_SECRET before launch so user links include secure_hash.
- BitLabs and Lootably are visibly marked “Not active yet”. Obtain their publisher token/placement ID and postback secret before changing the cards to active. The v13 database and postback function already accept provider values cpx, bitlabs, and lootably.
- Never put provider secrets in app.js or HTML.

Verification checklist
- Sign up requires consent and a 10-character password; password-reset email returns to /auth-confirm?mode=recovery.
- Signed-in Surveys returns a secure CPX URL; signed-out users are asked to sign in.
- Submit the same completed survey postback twice: balance increases only once.
- Reverse that event: coins are deducted once and an insufficient balance places the account under review.
- Submit support six times in one hour from the same address: the sixth request is rate-limited.
- Redeem a test reward: the request and coin hold succeed even if Resend is unavailable; when configured, both emails arrive.
- Reject the request: coins and reserved stock return exactly once, and the positive refund contributes to XP.
- Invalid non-Steam trade/proof URLs are rejected.
- Account deletion is blocked while a reward is pending, then removes the auth user and cascading profile data after resolution.
- /admin, /dashboard, /settings, /auth-confirm, and /steam-callback contain noindex and are absent from sitemap.xml.
- Install SkinQuest on iOS and Android; confirm clean routes work after reopening and the public shell opens offline.

Operational notes
- Do not run the full setup SQL on the existing project.
- Review the Privacy Policy with the final legal business/controller details before production launch; the package does not invent an address or company registration number.
- Keep the 1-coin Galil reward disabled until an administrator sets an intentional price and stock.
