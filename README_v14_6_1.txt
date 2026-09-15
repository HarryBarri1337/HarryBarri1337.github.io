SkinQuest v14.6.1 — reward layout and variant picker
===================================================
For an EXISTING live v14.6.0 installation:
1. Keep a copy of your currently deployed website files.
2. Upload the v14.6.1 website files, including the CSS/JS, HTML and sw.js.
3. Hard-refresh with Ctrl+Shift+R. The footer should say v14.6.1.
DO NOT run SQL again. The upgrade SQL is intentionally comments only.
NO Edge Function, secret or Cron changes. Keep the working Steam import.

Changes:
- Equal card sections align titles, descriptions, prices, stock, progress and buttons.
- Price and stock are separate rows so large coin values do not displace buttons.
- Single-listing and grouped cards reserve the same variant-info space.
- Variant tabs: Normal first, then Souvenir, then StatTrak when available.
- Souvenir is gold; StatTrak is orange, with text labels as well as colour.
- Wear rows sort FN, MW, FT, WW, BS. Unknown/container wear is Standard last.
- Coloured wear codes and full wear names, real coin prices and availability.
- Tab switching preserves the wear where available, otherwise selects the first
  existing wear in that tab. It never invents an unavailable item or merges stock.
- A direct variant link opens that exact variant and its type. Changing a row
  updates its permanent link, art, saved-goal state, price and delivery details.
- Keyboard-accessible tab navigation and selected-row indicators.
- Family cards no longer get an affordable-looking gold button solely because
  they have multiple variants. Exact checkout confirmation is unchanged.

Finance, users, orders, coin logic, support and the complete supabase/ directory
are unchanged from v14.6.0. This does not speed up/reset the Steam import.
The full setup is only for a BRAND-NEW installation; it has the same database
state as v14.6.0. Existing v14.6.0 users must not run it.
Read RELEASE_CHECKS_v14_6_1.txt for local checks and live UI checks.
The existing second-provider application guide remains included; no provider
has been activated. Never upload SQL, docs or supabase/ into the public web root.
