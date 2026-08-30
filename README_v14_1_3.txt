SkinQuest v14.1.3

UPDATE AN EXISTING v14.1.2 PROJECT
1. Run skinquest_upgrade_existing_to_v14_1_3.sql ONCE in Supabase SQL Editor.
2. Deploy these Edge Functions:
   - contact-email-start
   - contact-email-verify
   - reward-order-notify
3. Keep the existing RESEND_API_KEY and EMAIL_FROM secrets.
4. Optional but recommended: add a CONTACT_EMAIL_SECRET Edge Function secret with a long random value.
5. Copy/replace the public site files with this version.
6. Hard-refresh the site and test a Steam sign-in account on /dashboard.

FOR A BRAND-NEW EMPTY SUPABASE PROJECT
- Use skinquest_full_setup_v14_1_3.sql once.
- Deploy the existing project Edge Functions plus contact-email-start and contact-email-verify.
- Set the same existing email/survey secrets used by the project.

v14.1.3 UPDATE
- Steam-only accounts must add and verify a real contact email from a dashboard popup.
- The generated steam_<id>@steam.skinquestcs.com address remains auth-only and is no longer used for reward contact.
- Support auto-fill uses the verified contact email when available.
- Reward order emails use the verified contact email.
- Reward redemption is blocked server-side if a Steam-only account has no verified contact email.
- Trade links must belong to the connected Steam account (partner ID is matched to SteamID64).
- This does NOT guarantee that Steam currently allows the recipient to trade; temporary Steam Guard/device/password/trade cooldown restrictions are not exposed by the public trade URL itself.
