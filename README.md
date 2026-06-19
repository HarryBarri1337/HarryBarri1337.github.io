# SkinQuest

SkinQuest is a static frontend prototype for a CS2 skin reward site.

## Pages

- `index.html` - landing page
- `earn.html` - offerwall placeholder
- `rewards.html` - reward shop
- `dashboard.html` - user dashboard placeholder
- `how-it-works.html` - process explanation
- `terms.html` - placeholder terms
- `privacy.html` - placeholder privacy policy

## Important

This frontend does not credit demo coins. For real rewards, you need:

1. An offerwall provider account.
2. A backend server with a verified postback/webhook endpoint.
3. A database for users, balances, and redemptions.
4. Manual review or a secure Steam bot for payouts.

Never credit rewards from frontend JavaScript.


## Supabase

This version is connected to:

`https://ubvkupqgigfxehprsoit.supabase.co`

It uses the anon public key only. Do not add the service role key to frontend code.

## What works now

- Sign up
- Login
- Profile auto-creation
- Save Steam trade URL
- Load reward items from Supabase
- Create pending redemption requests if the user has enough points

## What does not exist yet

- Offerwall postbacks
- Automatic point crediting
- Admin dashboard
- Automatic Steam trades


## v5 changes

- Dark professional polish
- Coins wording instead of points
- Dashboard protected behind login
- Homepage changes CTA when logged in
- Trade-link helper button
- Level/XP display based on earned coins
- Subtle loading overlay to avoid auth-state flicker
