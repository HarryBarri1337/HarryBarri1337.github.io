-- SkinQuest v9 Supabase upgrade
-- Run this once in Supabase SQL Editor before using the v9 site.
-- It keeps your existing reward columns: id, name, points_coins, image_url, active, created_at.
-- It adds stock/reserve fields, admin fields, secure redeem RPCs, and RLS policies.

-- 1) Reward fields used by the v9 frontend/admin page
alter table public.reward_items
  add column if not exists quantity_total integer not null default 1,
  add column if not exists quantity_reserved integer not null default 0,
  add column if not exists rarity text,
  add column if not exists condition text,
  add column if not exists description text,
  add column if not exists market_name text,
  add column if not exists sort_order integer not null default 0;

-- If you previously added a v8 `quantity` column, copy it into the v9 stock field.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'reward_items' and column_name = 'quantity'
  ) then
    execute 'update public.reward_items set quantity_total = coalesce(quantity_total, quantity, 1) where quantity_total is null';
  end if;
end $$;

-- 2) Redemption request fields used by manual admin workflow
alter table public.redemption_requests
  add column if not exists admin_note text,
  add column if not exists trade_offer_url text,
  add column if not exists status_updated_at timestamptz,
  add column if not exists coins_refunded boolean not null default false,
  add column if not exists stock_released boolean not null default false,
  add column if not exists stock_finalized boolean not null default false,
  add column if not exists completed_at timestamptz,
  add column if not exists rejected_at timestamptz;

-- These are expected by the frontend. They probably already exist, but this makes the upgrade safer.
alter table public.redemption_requests
  add column if not exists reward_item_id bigint,
  add column if not exists reward_name text,
  add column if not exists points_cost integer,
  add column if not exists steam_trade_url text,
  add column if not exists status text not null default 'pending';

-- 3) Useful constraints. These blocks avoid duplicate-constraint errors.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'reward_items_quantity_total_nonnegative') then
    alter table public.reward_items add constraint reward_items_quantity_total_nonnegative check (quantity_total >= 0);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'reward_items_quantity_reserved_nonnegative') then
    alter table public.reward_items add constraint reward_items_quantity_reserved_nonnegative check (quantity_reserved >= 0);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'reward_items_reserved_not_above_total') then
    alter table public.reward_items add constraint reward_items_reserved_not_above_total check (quantity_reserved <= quantity_total);
  end if;
end $$;

-- 4) Admin helper: only Harry's email is admin.
create or replace function public.is_skinquest_admin()
returns boolean
language sql
stable
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'harrygotesson@gmail.com';
$$;

grant execute on function public.is_skinquest_admin() to anon, authenticated;

-- 5) Secure redeem function.
-- The frontend calls this instead of manually updating balance/stock/request in separate JS steps.
create or replace function public.redeem_reward(p_reward_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_reward public.reward_items%rowtype;
  v_cost integer;
  v_available integer;
  v_request_id bigint;
begin
  if v_user_id is null then
    raise exception 'You must be logged in to redeem rewards.';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  if not found then
    raise exception 'Profile was not found.';
  end if;

  if coalesce(v_profile.steam_trade_url, '') = '' then
    raise exception 'Save your Steam trade URL before redeeming.';
  end if;

  select * into v_reward
  from public.reward_items
  where id = p_reward_id and active = true
  for update;

  if not found then
    raise exception 'Reward not found or inactive.';
  end if;

  v_cost := coalesce(v_reward.points_coins, 0);

  if v_cost <= 0 then
    raise exception 'Reward has an invalid coin price.';
  end if;

  v_available := coalesce(v_reward.quantity_total, 0) - coalesce(v_reward.quantity_reserved, 0);

  if v_available <= 0 then
    raise exception 'That reward is out of stock.';
  end if;

  if coalesce(v_profile.points_balance, 0) < v_cost then
    raise exception 'Not enough coins.';
  end if;

  update public.profiles
  set points_balance = points_balance - v_cost
  where id = v_user_id;

  update public.reward_items
  set quantity_reserved = quantity_reserved + 1
  where id = p_reward_id;

  insert into public.redemption_requests (
    user_id,
    reward_item_id,
    reward_name,
    points_cost,
    steam_trade_url,
    status,
    status_updated_at
  ) values (
    v_user_id,
    v_reward.id,
    v_reward.name,
    v_cost,
    v_profile.steam_trade_url,
    'pending',
    now()
  ) returning id into v_request_id;

  insert into public.coin_adjustments (user_id, amount, reason)
  values (v_user_id, -v_cost, 'Redeem pending / ' || v_reward.name);

  return jsonb_build_object('ok', true, 'request_id', v_request_id);
end;
$$;

grant execute on function public.redeem_reward(bigint) to authenticated;

-- 6) Admin status function.
-- completed: finalizes reserved stock.
-- rejected/refunded/cancelled: refunds coins and releases reserved stock if not already done.
create or replace function public.admin_update_redemption_status(
  p_request_id bigint,
  p_status text,
  p_admin_note text default null,
  p_trade_offer_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.redemption_requests%rowtype;
  v_points integer;
begin
  if not public.is_skinquest_admin() then
    raise exception 'Admin access required.';
  end if;

  if p_status not in ('pending', 'reviewing', 'trade_sent', 'completed', 'rejected', 'refunded', 'cancelled') then
    raise exception 'Invalid status.';
  end if;

  select * into v_request
  from public.redemption_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Redeem request not found.';
  end if;

  v_points := coalesce(v_request.points_cost, 0);

  -- Refund and release reserved stock for negative/closed statuses.
  if p_status in ('rejected', 'refunded', 'cancelled') then
    if not coalesce(v_request.coins_refunded, false) and v_points > 0 then
      update public.profiles
      set points_balance = points_balance + v_points
      where id = v_request.user_id;

      insert into public.coin_adjustments (user_id, amount, reason)
      values (v_request.user_id, v_points, 'Refund / ' || coalesce(v_request.reward_name, 'reward'));
    end if;

    if not coalesce(v_request.stock_released, false) and not coalesce(v_request.stock_finalized, false) and v_request.reward_item_id is not null then
      update public.reward_items
      set quantity_reserved = greatest(quantity_reserved - 1, 0)
      where id = v_request.reward_item_id and quantity_reserved > 0;
    end if;

    update public.redemption_requests
    set status = p_status,
        admin_note = nullif(p_admin_note, ''),
        trade_offer_url = nullif(p_trade_offer_url, ''),
        status_updated_at = now(),
        rejected_at = case when p_status in ('rejected', 'refunded', 'cancelled') then now() else rejected_at end,
        coins_refunded = true,
        stock_released = true
    where id = p_request_id;

    return jsonb_build_object('ok', true, 'status', p_status, 'refunded', true);
  end if;

  -- Complete means the reserved item was actually sent.
  if p_status = 'completed' then
    if not coalesce(v_request.stock_finalized, false) and not coalesce(v_request.stock_released, false) and v_request.reward_item_id is not null then
      update public.reward_items
      set quantity_reserved = greatest(quantity_reserved - 1, 0),
          quantity_total = greatest(quantity_total - 1, 0)
      where id = v_request.reward_item_id and quantity_reserved > 0;
    end if;

    update public.redemption_requests
    set status = p_status,
        admin_note = nullif(p_admin_note, ''),
        trade_offer_url = nullif(p_trade_offer_url, ''),
        status_updated_at = now(),
        completed_at = now(),
        stock_finalized = true
    where id = p_request_id;

    return jsonb_build_object('ok', true, 'status', p_status, 'completed', true);
  end if;

  -- Non-final status changes: pending/reviewing/trade_sent.
  update public.redemption_requests
  set status = p_status,
      admin_note = nullif(p_admin_note, ''),
      trade_offer_url = nullif(p_trade_offer_url, ''),
      status_updated_at = now()
  where id = p_request_id;

  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;

grant execute on function public.admin_update_redemption_status(bigint, text, text, text) to authenticated;

-- 7) RLS policies. These make the static frontend safer.
-- Service-role backend/postbacks still bypass RLS.
alter table public.reward_items enable row level security;
alter table public.profiles enable row level security;
alter table public.redemption_requests enable row level security;
alter table public.coin_adjustments enable row level security;

-- reward_items
drop policy if exists "Reward items are public when active" on public.reward_items;
drop policy if exists "Admin can read all reward items" on public.reward_items;
drop policy if exists "Admin can insert reward items" on public.reward_items;
drop policy if exists "Admin can update reward items" on public.reward_items;
drop policy if exists "Admin can delete reward items" on public.reward_items;

create policy "Reward items are public when active"
on public.reward_items
for select
using (active = true or public.is_skinquest_admin());

create policy "Admin can insert reward items"
on public.reward_items
for insert
with check (public.is_skinquest_admin());

create policy "Admin can update reward items"
on public.reward_items
for update
using (public.is_skinquest_admin())
with check (public.is_skinquest_admin());

create policy "Admin can delete reward items"
on public.reward_items
for delete
using (public.is_skinquest_admin());

-- profiles
drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Admin can read all profiles" on public.profiles;
drop policy if exists "Admin can update all profiles" on public.profiles;

create policy "Users can read own profile"
on public.profiles
for select
using (auth.uid() = id or public.is_skinquest_admin());

create policy "Users can insert own profile"
on public.profiles
for insert
with check (auth.uid() = id);

create policy "Users can update own profile"
on public.profiles
for update
using (auth.uid() = id or public.is_skinquest_admin())
with check (auth.uid() = id or public.is_skinquest_admin());

-- redemption_requests
drop policy if exists "Users can read own redemption requests" on public.redemption_requests;
drop policy if exists "Users can insert own redemption requests" on public.redemption_requests;
drop policy if exists "Admin can read all redemption requests" on public.redemption_requests;
drop policy if exists "Admin can update all redemption requests" on public.redemption_requests;

create policy "Users can read own redemption requests"
on public.redemption_requests
for select
using (auth.uid() = user_id or public.is_skinquest_admin());

create policy "Users can insert own redemption requests"
on public.redemption_requests
for insert
with check (auth.uid() = user_id);

create policy "Admin can update all redemption requests"
on public.redemption_requests
for update
using (public.is_skinquest_admin())
with check (public.is_skinquest_admin());

-- coin_adjustments
drop policy if exists "Users can read own coin adjustments" on public.coin_adjustments;
drop policy if exists "Admin can read all coin adjustments" on public.coin_adjustments;
drop policy if exists "Admin can insert coin adjustments" on public.coin_adjustments;

create policy "Users can read own coin adjustments"
on public.coin_adjustments
for select
using (auth.uid() = user_id or public.is_skinquest_admin());

create policy "Admin can insert coin adjustments"
on public.coin_adjustments
for insert
with check (public.is_skinquest_admin());

-- 8) Useful admin commands:
-- Hide a reward instead of deleting it:
-- update public.reward_items set active = false where id = 10;
-- Check why id 10 cannot be deleted:
-- select * from public.redemption_requests where reward_item_id = 10;
