-- SkinQuest v8.3 rewards upgrade
-- Run this in Supabase SQL Editor.
-- Keeps your existing columns: id, name, points_coins, image_url, active, created_at.
-- Adds optional fields that the website now reads directly from Supabase.

alter table public.reward_items
  add column if not exists quantity integer not null default 1,
  add column if not exists rarity text,
  add column if not exists condition text,
  add column if not exists description text,
  add column if not exists market_name text,
  add column if not exists sort_order integer default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'reward_items_quantity_nonnegative'
  ) then
    alter table public.reward_items
      add constraint reward_items_quantity_nonnegative check (quantity >= 0);
  end if;
end $$;

-- Optional example row. Change values before running if you want.
-- insert into public.reward_items
--   (name, points_coins, image_url, quantity, rarity, condition, description, active, sort_order)
-- values
--   ('AK-47 | Slate', 900, 'assets/rewards/ak-slate.png', 2, 'restricted', 'FT', 'Manual Steam trade', true, 10);

-- To hide a reward instead of deleting it:
-- update public.reward_items set active = false where id = 10;
