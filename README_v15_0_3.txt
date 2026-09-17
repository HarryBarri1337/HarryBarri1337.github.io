SkinQuest v15.0.3
================

This is a customer-interface update to the working v15.0.2 site.
No wallet, order, provider, database or server-side security logic has changed.

UPDATING YOUR LIVE v15.0.2 SITE
1. Back up your existing website files.
2. Upload the website files from this folder. Upload JavaScript/CSS/assets first
   and HTML files last, so the new HTML cannot request missing new assets.
3. Keep your existing hosting configuration and environment settings.
4. Hard refresh once (Ctrl+F5 on desktop). The PWA cache moves to v1503.
5. Check signed-in navigation, a reward card, Saved rewards, My orders,
   Coin history > Show more > Show less, and both survey providers.
6. Check on a real mobile phone before announcing the update.

DO NOT repeat SQL imports, Edge Function deploys, secrets or Cron setup.
The SQL upgrade file has comments only. The full setup is unchanged from v15.0.2
and is included only for a new empty installation, not for this live update.
Do not upload SQL files, README/check files or the supabase folder to your public
website directory. Existing .htaccess route/security rules must remain active.

WHAT CHANGED
- Compact centered reward cards: four across on desktop, three on tablets,
  two on phones. The whole card opens the exact reward page; the star is separate.
- Reward variants stay grouped. Removed the grouping switch, variant counts,
  customer Steam-linked badges, redundant card buttons and empty progress space.
- Current-price and stale-price ordering guards are preserved.
- Availability buttons have equal widths and centered labels.
- Dashboard top and level progress are centered; recommendation banner removed.
- My orders is the single order-history page. Dashboard keeps a linked summary.
- Coin history begins with three entries, with Show more, filters and Show less.
- Internal unassigned/grouping headings are removed from customer order lists.
- Help is back in the main menu. Header and page widths remain aligned.
- CPX sidebar and survey panel stretch to the same desktop row height.
- Search fields show one border indicator, not nested gold outlines.
- Checkboxes keep their normal size, without mouse-focus glow; keyboard focus
  remains visible and the surrounding select-group label remains easy to click.

LIVE CHECKS
Local browser checks use mock accounts/provider responses, not your production
database or actual survey completions. Provider links and credits must also be
checked against your configured live account; no local check proves payment.
