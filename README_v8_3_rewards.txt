SkinQuest v8.3 rewards update

What changed:
- Rewards now use Supabase fields directly instead of guessing rarity from the item name.
- The frontend reads: name, points_coins, image_url, active, quantity, rarity, condition, description.
- If rarity is empty, no rarity badge is shown.
- If quantity is 0, redeem is disabled and shows Out of stock.
- The app now orders rewards by points_coins, matching your current reward_items table.
- The assets folder was not modified.

Supabase steps:
1. Open Supabase > SQL Editor.
2. Run reward_items_upgrade_v8_3.sql.
3. Go to Table Editor > reward_items.
4. Fill in rarity, condition, quantity, description and image_url for each item.
5. Refresh the GitHub Pages site with Ctrl+F5.

Suggested rarity values:
consumer, industrial, milspec, restricted, classified, covert, contraband

Suggested condition values:
FN, MW, FT, WW, BS

Why reward id 10 may not delete:
It is probably referenced by redemption_requests through reward_item_id. Supabase/Postgres blocks deleting parent rows when another table still points at them. Usually use active = false instead of deleting rewards, because old redeem history should keep working.
