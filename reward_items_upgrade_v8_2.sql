-- SkinQuest v8.2 reward shop upgrade
-- Run this in Supabase SQL Editor.
-- It adds image, quantity/stock, rarity, condition and description support to reward_items.

alter table public.reward_items
  add column if not exists image_url text,
  add column if not exists quantity integer not null default 1,
  add column if not exists rarity text default 'milspec',
  add column if not exists condition text,
  add column if not exists description text,
  add column if not exists market_name text,
  add column if not exists sort_order integer default 0;

-- Optional safety: no negative stock.
do $$ begin
  alter table public.reward_items
    add constraint reward_items_quantity_nonnegative check (quantity >= 0);
exception
  when duplicate_object then null;
end $$;

-- Example format. Replace these with YOUR real rewards and image links.
-- Tip: upload images to your GitHub repo, for example /assets/rewards/ak-slate.png,
-- then use image_url = 'assets/rewards/ak-slate.png'.

-- insert into public.reward_items
--   (name, market_name, points_cost, image_url, quantity, rarity, condition, description, active, sort_order)
-- values
--   ('AK-47 | Slate', 'AK-47 | Slate (Field-Tested)', 900, 'assets/rewards/ak-slate.png', 2, 'restricted', 'FT', 'Real CS2 skin reward · manual Steam trade', true, 10),
--   ('AWP | Atheris', 'AWP | Atheris (Field-Tested)', 750, 'assets/rewards/awp-atheris.png', 1, 'restricted', 'FT', 'Real CS2 skin reward · manual Steam trade', true, 20),
--   ('Glock-18 | Moonrise', 'Glock-18 | Moonrise (Minimal Wear)', 450, 'assets/rewards/glock-moonrise.png', 3, 'restricted', 'MW', 'Real CS2 skin reward · manual Steam trade', true, 30);

-- If you already have rewards, update them like this:
-- update public.reward_items
-- set image_url = 'assets/rewards/your-image.png',
--     quantity = 1,
--     rarity = 'milspec',
--     condition = 'FT',
--     description = 'Real CS2 skin reward · manual Steam trade'
-- where name = 'YOUR ITEM NAME';
