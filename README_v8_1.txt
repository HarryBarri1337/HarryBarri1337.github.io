v8.1 fixes broken auth/click handlers, makes CPX button a real anchor, and adds hover states.

v8.2 reward shop upgrade:
- rewards.html now supports real item images using reward_items.image_url
- reward cards show quantity/stock, rarity, condition, and description
- out-of-stock rewards are disabled
- redeeming decrements quantity when the quantity column exists
- run reward_items_upgrade_v8_2.sql in Supabase before using stock/images
