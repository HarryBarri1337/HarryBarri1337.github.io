SkinQuest v14.2.0

UPDATE AN EXISTING v14.1.3 OR v14.1.4 PROJECT
1. Run skinquest_upgrade_existing_to_v14_2_0.sql ONCE in Supabase SQL Editor.
2. In Supabase Edge Functions, ADD a function named: password-reset-request
3. Paste the full contents of supabase/functions/password-reset-request/index.ts into that function and deploy/save it.
4. No other Edge Functions need to be added or edited for v14.2.0.
5. Replace/upload the public site files with this version.
6. Hard-refresh the site (Ctrl+Shift+R).

No new secret is required. password-reset-request uses RATE_LIMIT_SECRET if you already have it; otherwise it safely falls back to the service-role key for hashing the rate-limit key.

FOR A BRAND-NEW EMPTY SUPABASE PROJECT
- Use skinquest_full_setup_v14_2_0.sql once.
- Deploy all Edge Functions in supabase/functions, including password-reset-request.

v14.2.0 UPDATE
- Forgot password is now routed through password-reset-request.
- The backend allows one accepted reset-email request per normalized email address every 60 seconds.
- Simultaneous clicks for the same email are serialized in Postgres, so they cannot both pass the limiter.
- The Forgot password button displays a countdown after a successful request or a 429 cooldown response.
- Password-reset responses remain generic so the UI does not reveal whether an email has an account.
- The auth modal only closes from a genuine backdrop press. Dragging a text selection from an input outside the dialog and releasing no longer closes it.

v14.1.4 FIXES RETAINED
- Personal notifications are restricted to the signed-in user's own rows.
- Mark all read matches the notifications shown.
- Notification drawer close behavior remains fixed after header/auth re-renders.

v14.1.3 FEATURES RETAINED
- Steam-only accounts must add and verify a real contact email from a dashboard popup.
- Support and reward emails use the verified contact email instead of the synthetic Steam auth address.
- Reward redemption is blocked server-side until Steam-only users have a verified contact email.
- Trade links must belong to the connected Steam account.
