# SkinQuest v9

Main changes:

- Rewards are fully managed from Supabase/admin instead of hardcoded frontend rarity/condition/stock.
- Admin page is hidden unless the logged-in email is harrygotesson@gmail.com.
- Admin page can add/edit/hide rewards and manually change redeem request statuses.
- Redeeming now uses the Supabase RPC function `redeem_reward(p_reward_id)`.
- Coins + stock are handled in one database transaction instead of separate frontend updates.
- Reward stock now supports total, reserved, and available counts.
- Dashboard now shows coin history and better redeem statuses.
- Steam trade URL is validated before saving/redeeming.
- `assets/` is not included in this zip and should not be overwritten.

Required Supabase step:

Run `skinquest_v9_supabase_upgrade.sql` in Supabase SQL Editor.

After that:

1. Upload this zip's files to GitHub, but do not replace your existing `assets/` folder.
2. In Supabase, check `reward_items` and edit rewards from the new admin page or Table Editor.
3. Image paths can stay like `assets/rewards/example.png`.
4. Redeems should appear in admin where you can mark pending, reviewing, trade sent, completed, rejected, refunded, or cancelled.

Important:

The offerwall link was not changed. If your postback already credits `profiles.points_balance` and logs `coin_adjustments`, it can keep working.
