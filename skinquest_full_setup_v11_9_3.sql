-- SkinQuest full Supabase setup v11.9.3
-- Run this in Supabase SQL Editor before public testing.
-- It creates the tables, RLS policies, and RPC functions used by the v11.9.3 frontend.

create extension if not exists pgcrypto;

-- -----------------------------
-- Tables
-- -----------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  points_balance integer not null default 0,
  level_bonus_claimed_up_to integer not null default 1,
  steam_trade_url text,
  steam_id text,
  steam_name text,
  steam_avatar_url text,
  steam_connected_at timestamptz,
  account_status text not null default 'active',
  notification_reward_updates boolean not null default true,
  notification_offer_issues boolean not null default true,
  notification_product_updates boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists points_balance integer not null default 0;
alter table public.profiles add column if not exists level_bonus_claimed_up_to integer not null default 1;
alter table public.profiles add column if not exists steam_trade_url text;
alter table public.profiles add column if not exists steam_id text;
alter table public.profiles add column if not exists steam_name text;
alter table public.profiles add column if not exists steam_avatar_url text;
alter table public.profiles add column if not exists steam_connected_at timestamptz;
alter table public.profiles add column if not exists account_status text not null default 'active';
alter table public.profiles add column if not exists notification_reward_updates boolean not null default true;
alter table public.profiles add column if not exists notification_offer_issues boolean not null default true;
alter table public.profiles add column if not exists notification_product_updates boolean not null default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'admin',
  created_at timestamptz not null default now()
);

alter table public.admin_users add column if not exists role text not null default 'admin';
do $$
begin
  alter table public.admin_users add constraint admin_users_role_check check (role in ('admin', 'owner'));
exception when duplicate_object then null;
end $$;

create table if not exists public.reward_items (
  id bigserial primary key,
  name text not null,
  market_name text,
  description text,
  image_url text,
  rarity text,
  condition text,
  points_coins integer not null default 0,
  points_cost integer not null default 0,
  quantity_total integer not null default 1,
  quantity_reserved integer not null default 0,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.reward_items add column if not exists market_name text;
alter table public.reward_items add column if not exists description text;
alter table public.reward_items add column if not exists image_url text;
alter table public.reward_items add column if not exists rarity text;
alter table public.reward_items add column if not exists condition text;
alter table public.reward_items add column if not exists points_coins integer not null default 0;
alter table public.reward_items add column if not exists points_cost integer not null default 0;
alter table public.reward_items add column if not exists quantity_total integer not null default 1;
alter table public.reward_items add column if not exists quantity_reserved integer not null default 0;
alter table public.reward_items add column if not exists active boolean not null default true;
alter table public.reward_items add column if not exists sort_order integer not null default 0;
alter table public.reward_items add column if not exists created_at timestamptz not null default now();
alter table public.reward_items add column if not exists updated_at timestamptz not null default now();

create table if not exists public.redemption_requests (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_id bigint references public.reward_items(id) on delete set null,
  reward_name text not null,
  points_coins integer not null default 0,
  points_cost integer not null default 0,
  steam_trade_url text,
  status text not null default 'pending',
  admin_note text,
  trade_offer_url text,
  refunded_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.redemption_requests add column if not exists points_coins integer not null default 0;
alter table public.redemption_requests add column if not exists points_cost integer not null default 0;
alter table public.redemption_requests add column if not exists steam_trade_url text;
alter table public.redemption_requests add column if not exists admin_note text;
alter table public.redemption_requests add column if not exists trade_offer_url text;
alter table public.redemption_requests add column if not exists refunded_at timestamptz;
alter table public.redemption_requests add column if not exists completed_at timestamptz;
alter table public.redemption_requests add column if not exists updated_at timestamptz not null default now();

create table if not exists public.coin_adjustments (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null,
  reason text,
  source_type text,
  source_id text,
  created_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.coin_adjustments add column if not exists source_type text;
alter table public.coin_adjustments add column if not exists source_id text;
alter table public.coin_adjustments add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.coin_adjustments add column if not exists metadata jsonb not null default '{}'::jsonb;

create table if not exists public.offerwall_events (
  id bigserial primary key,
  provider text not null,
  provider_event_id text not null,
  user_id uuid references auth.users(id) on delete set null,
  amount integer not null default 0,
  status text not null default 'pending',
  raw_payload jsonb not null default '{}'::jsonb,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(provider, provider_event_id)
);

create table if not exists public.linked_services (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  provider_user_id text,
  display_name text,
  avatar_url text,
  status text not null default 'planned',
  metadata jsonb not null default '{}'::jsonb,
  linked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, provider)
);

create table if not exists public.steam_auth_states (
  state text primary key,
  user_id uuid references auth.users(id) on delete cascade,
  mode text not null default 'connect',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.steam_auth_states alter column user_id drop not null;
alter table public.steam_auth_states add column if not exists mode text not null default 'connect';

create table if not exists public.support_requests (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete set null,
  topic text not null,
  message text not null,
  page_url text,
  user_agent text,
  account_email text,
  browser_language text,
  status text not null default 'new',
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.support_requests add column if not exists page_url text;
alter table public.support_requests add column if not exists user_agent text;
alter table public.support_requests add column if not exists account_email text;
alter table public.support_requests add column if not exists browser_language text;
alter table public.support_requests add column if not exists admin_note text;
alter table public.support_requests add column if not exists updated_at timestamptz not null default now();

create index if not exists profiles_account_status_idx on public.profiles(account_status);
create unique index if not exists profiles_steam_id_unique_idx on public.profiles(steam_id) where steam_id is not null;
create index if not exists steam_auth_states_user_id_idx on public.steam_auth_states(user_id);
create index if not exists steam_auth_states_expires_at_idx on public.steam_auth_states(expires_at);
create index if not exists reward_items_active_sort_idx on public.reward_items(active, sort_order, points_coins);
create index if not exists redemption_requests_user_created_idx on public.redemption_requests(user_id, created_at desc);
create index if not exists redemption_requests_status_created_idx on public.redemption_requests(status, created_at desc);
create index if not exists coin_adjustments_user_created_idx on public.coin_adjustments(user_id, created_at desc);
create index if not exists offerwall_events_user_created_idx on public.offerwall_events(user_id, created_at desc);
create index if not exists linked_services_user_provider_idx on public.linked_services(user_id, provider);
create index if not exists support_requests_status_created_idx on public.support_requests(status, created_at desc);
create index if not exists support_requests_user_created_idx on public.support_requests(user_id, created_at desc);

-- -----------------------------
-- Helpers and triggers
-- -----------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists reward_items_set_updated_at on public.reward_items;
create trigger reward_items_set_updated_at
before update on public.reward_items
for each row execute function public.set_updated_at();

drop trigger if exists redemption_requests_set_updated_at on public.redemption_requests;
create trigger redemption_requests_set_updated_at
before update on public.redemption_requests
for each row execute function public.set_updated_at();

drop trigger if exists linked_services_set_updated_at on public.linked_services;
create trigger linked_services_set_updated_at
before update on public.linked_services
for each row execute function public.set_updated_at();

drop trigger if exists support_requests_set_updated_at on public.support_requests;
create trigger support_requests_set_updated_at
before update on public.support_requests
for each row execute function public.set_updated_at();

create or replace function public.sync_reward_points_cost()
returns trigger
language plpgsql
as $$
begin
  if new.points_coins is null or new.points_coins <= 0 then
    new.points_coins := coalesce(nullif(new.points_cost, 0), 0);
  end if;
  if new.points_cost is null or new.points_cost <= 0 then
    new.points_cost := coalesce(new.points_coins, 0);
  end if;
  return new;
end;
$$;

drop trigger if exists reward_items_sync_points on public.reward_items;
create trigger reward_items_sync_points
before insert or update on public.reward_items
for each row execute function public.sync_reward_points_cost();

-- -----------------------------
-- Security helpers
-- -----------------------------

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
  );
$$;

create or replace function public.get_admin_role()
returns text
language sql
security definer
set search_path = public
as $$
  select au.role
  from public.admin_users au
  where au.user_id = auth.uid()
  limit 1;
$$;

create or replace function public.is_owner()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce(public.get_admin_role() = 'owner', false);
$$;

create or replace function public.ensure_skinquest_profile()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := coalesce(auth.jwt() ->> 'email', '');
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  insert into public.profiles (id, username)
  values (v_user_id, coalesce(nullif(split_part(v_email, '@', 1), ''), 'user'))
  on conflict (id) do nothing;

  select * into v_profile from public.profiles where id = v_user_id;
  return v_profile;
end;
$$;

create or replace function public.save_skinquest_trade_url(p_trade_url text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_trade_url text := nullif(trim(coalesce(p_trade_url, '')), '');
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  perform public.ensure_skinquest_profile();

  if v_trade_url is not null and v_trade_url !~ '^https://steamcommunity\.com/tradeoffer/new/\?(.+&)?partner=[0-9]+(&.+)?token=[A-Za-z0-9_-]+' then
    raise exception 'Invalid Steam trade URL.';
  end if;

  update public.profiles
  set steam_trade_url = v_trade_url
  where id = v_user_id
  returning * into v_profile;

  return v_profile;
end;
$$;

create or replace function public.save_account_settings(
  p_notification_reward_updates boolean default true,
  p_notification_offer_issues boolean default true,
  p_notification_product_updates boolean default false
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  perform public.ensure_skinquest_profile();

  update public.profiles
  set notification_reward_updates = coalesce(p_notification_reward_updates, true),
      notification_offer_issues = coalesce(p_notification_offer_issues, true),
      notification_product_updates = coalesce(p_notification_product_updates, false)
  where id = v_user_id
  returning * into v_profile;

  return v_profile;
end;
$$;

create or replace function public.claim_level_rewards()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_base_earned integer := 0;
  v_current_level integer := 1;
  v_claimed_level integer := 1;
  v_bonus integer := 0;
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  perform public.ensure_skinquest_profile();

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  select coalesce(sum(amount), 0)::integer into v_base_earned
  from public.coin_adjustments
  where user_id = v_user_id
    and amount > 0
    and lower(coalesce(reason, '')) not like 'level reward%';

  v_current_level := greatest(1, floor(v_base_earned / 1000.0)::integer + 1);
  v_claimed_level := greatest(1, coalesce(v_profile.level_bonus_claimed_up_to, 1));

  if v_current_level > v_claimed_level then
    v_bonus := (v_current_level - v_claimed_level) * 50;

    update public.profiles
    set points_balance = coalesce(points_balance, 0) + v_bonus,
        level_bonus_claimed_up_to = v_current_level
    where id = v_user_id;

    insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, metadata)
    values (
      v_user_id,
      v_bonus,
      'Level reward / Level ' || (v_claimed_level + 1)::text || case when v_current_level > v_claimed_level + 1 then ' to ' || v_current_level::text else '' end,
      'level_reward',
      v_current_level::text,
      jsonb_build_object('from_level', v_claimed_level, 'to_level', v_current_level)
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'earned_coins', v_base_earned,
    'level', v_current_level,
    'claimed_level', greatest(v_claimed_level, v_current_level),
    'bonus_awarded', v_bonus
  );
end;
$$;

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
    raise exception 'You must be logged in.';
  end if;

  perform public.ensure_skinquest_profile();

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  if coalesce(v_profile.account_status, 'active') <> 'active' then
    raise exception 'Account is not active.';
  end if;

  if nullif(trim(coalesce(v_profile.steam_trade_url, '')), '') is null then
    raise exception 'Steam trade URL is required.';
  end if;

  select * into v_reward
  from public.reward_items
  where id = p_reward_id and active = true
  for update;

  if not found then
    raise exception 'Reward not found.';
  end if;

  v_cost := coalesce(nullif(v_reward.points_coins, 0), v_reward.points_cost, 0);
  if v_cost <= 0 then
    raise exception 'Reward price is invalid.';
  end if;

  v_available := greatest(0, coalesce(v_reward.quantity_total, 0) - coalesce(v_reward.quantity_reserved, 0));
  if v_available <= 0 then
    raise exception 'Reward is out of stock.';
  end if;

  if coalesce(v_profile.points_balance, 0) < v_cost then
    raise exception 'Not enough coins.';
  end if;

  update public.profiles
  set points_balance = points_balance - v_cost
  where id = v_user_id;

  update public.reward_items
  set quantity_reserved = coalesce(quantity_reserved, 0) + 1
  where id = v_reward.id;

  insert into public.redemption_requests (
    user_id, reward_id, reward_name, points_coins, points_cost, steam_trade_url, status
  ) values (
    v_user_id, v_reward.id, v_reward.name, v_cost, v_cost, v_profile.steam_trade_url, 'pending'
  ) returning id into v_request_id;

  insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, metadata)
  values (
    v_user_id,
    -v_cost,
    'Redeem hold / ' || v_reward.name,
    'redemption_hold',
    v_request_id::text,
    jsonb_build_object('reward_id', v_reward.id, 'reward_name', v_reward.name)
  );

  return jsonb_build_object('ok', true, 'request_id', v_request_id);
end;
$$;

create or replace function public.owner_set_admin_role(
  p_user_identifier text,
  p_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
  v_role text := lower(trim(coalesce(p_role, '')));
begin
  if not public.is_owner() then
    raise exception 'Owner access required.';
  end if;

  begin
    v_user_id := p_user_identifier::uuid;
  exception when others then
    v_user_id := null;
  end;

  if v_user_id is null then
    select id into v_user_id
    from auth.users
    where lower(email) = lower(trim(p_user_identifier))
    limit 1;
  end if;

  if v_user_id is null then
    raise exception 'User not found.';
  end if;

  if v_role in ('remove', 'none', 'user', '') then
    delete from public.admin_users where user_id = v_user_id;
    return jsonb_build_object('ok', true, 'user_id', v_user_id, 'role', null);
  end if;

  if v_role not in ('admin', 'owner') then
    raise exception 'Invalid role.';
  end if;

  insert into public.admin_users (user_id, role)
  values (v_user_id, v_role)
  on conflict (user_id) do update set role = excluded.role;

  return jsonb_build_object('ok', true, 'user_id', v_user_id, 'role', v_role);
end;
$$;

create or replace function public.admin_adjust_user_coins(
  p_user_identifier text,
  p_amount integer,
  p_reason text default 'Manual admin adjustment'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin_id uuid := auth.uid();
  v_user_id uuid;
  v_reason text := coalesce(nullif(trim(p_reason), ''), 'Manual admin adjustment');
begin
  if not public.is_owner() then
    raise exception 'Owner access required.';
  end if;

  if p_amount is null or p_amount = 0 then
    raise exception 'Amount must not be zero.';
  end if;

  begin
    v_user_id := p_user_identifier::uuid;
  exception when others then
    v_user_id := null;
  end;

  if v_user_id is null then
    select id into v_user_id
    from auth.users
    where lower(email) = lower(trim(p_user_identifier))
    limit 1;
  end if;

  if v_user_id is null then
    raise exception 'User not found.';
  end if;

  insert into public.profiles (id, username)
  values (v_user_id, 'user')
  on conflict (id) do nothing;

  update public.profiles
  set points_balance = greatest(0, coalesce(points_balance, 0) + p_amount)
  where id = v_user_id;

  insert into public.coin_adjustments (user_id, amount, reason, source_type, created_by)
  values (v_user_id, p_amount, v_reason, 'admin_adjustment', v_admin_id);

  return jsonb_build_object('ok', true, 'user_id', v_user_id, 'amount', p_amount);
end;
$$;

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
  v_admin_id uuid := auth.uid();
  v_request public.redemption_requests%rowtype;
  v_old_status text;
  v_cost integer;
  v_release_stock boolean := false;
  v_refund boolean := false;
begin
  if not public.is_admin() then
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
    raise exception 'Request not found.';
  end if;

  v_old_status := v_request.status;
  v_cost := coalesce(nullif(v_request.points_coins, 0), v_request.points_cost, 0);

  if p_status in ('rejected', 'refunded', 'cancelled') and v_request.refunded_at is null then
    v_refund := true;
    v_release_stock := v_old_status not in ('completed');
  elsif p_status = 'completed' and v_request.completed_at is null then
    v_release_stock := true;
  end if;

  if v_refund then
    update public.profiles
    set points_balance = coalesce(points_balance, 0) + v_cost
    where id = v_request.user_id;

    insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, created_by, metadata)
    values (
      v_request.user_id,
      v_cost,
      'Redeem refund / ' || v_request.reward_name,
      'redemption_refund',
      v_request.id::text,
      v_admin_id,
      jsonb_build_object('old_status', v_old_status, 'new_status', p_status)
    );
  end if;

  if v_release_stock and v_request.reward_id is not null then
    if p_status = 'completed' then
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved, 0) - 1),
          quantity_total = greatest(0, coalesce(quantity_total, 0) - 1)
      where id = v_request.reward_id;
    else
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved, 0) - 1)
      where id = v_request.reward_id;
    end if;
  end if;

  update public.redemption_requests
  set status = p_status,
      admin_note = nullif(p_admin_note, ''),
      trade_offer_url = nullif(p_trade_offer_url, ''),
      refunded_at = case when v_refund then now() else refunded_at end,
      completed_at = case when p_status = 'completed' then coalesce(completed_at, now()) else completed_at end
  where id = p_request_id;

  return jsonb_build_object('ok', true, 'request_id', p_request_id, 'status', p_status, 'refunded', v_refund);
end;
$$;

-- -----------------------------
-- RLS policies
-- -----------------------------

alter table public.profiles enable row level security;
alter table public.admin_users enable row level security;
alter table public.reward_items enable row level security;
alter table public.redemption_requests enable row level security;
alter table public.coin_adjustments enable row level security;
alter table public.offerwall_events enable row level security;
alter table public.linked_services enable row level security;
alter table public.steam_auth_states enable row level security;
alter table public.support_requests enable row level security;

drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists admin_users_select_own_or_admin on public.admin_users;
create policy admin_users_select_own_or_admin on public.admin_users
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists reward_items_select_active on public.reward_items;
create policy reward_items_select_active on public.reward_items
for select to anon, authenticated
using (active = true or public.is_admin());

drop policy if exists reward_items_admin_insert on public.reward_items;
create policy reward_items_admin_insert on public.reward_items
for insert to authenticated
with check (public.is_owner());

drop policy if exists reward_items_admin_update on public.reward_items;
create policy reward_items_admin_update on public.reward_items
for update to authenticated
using (public.is_owner())
with check (public.is_owner());

drop policy if exists redemption_requests_select_own_or_admin on public.redemption_requests;
create policy redemption_requests_select_own_or_admin on public.redemption_requests
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists coin_adjustments_select_own_or_admin on public.coin_adjustments;
create policy coin_adjustments_select_own_or_admin on public.coin_adjustments
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists offerwall_events_admin_select on public.offerwall_events;
create policy offerwall_events_admin_select on public.offerwall_events
for select to authenticated
using (public.is_admin());

drop policy if exists linked_services_select_own_or_admin on public.linked_services;
create policy linked_services_select_own_or_admin on public.linked_services
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists support_requests_select_own_or_admin on public.support_requests;
create policy support_requests_select_own_or_admin on public.support_requests
for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists support_requests_insert_own on public.support_requests;
drop policy if exists support_requests_insert_contact on public.support_requests;
create policy support_requests_insert_contact on public.support_requests
for insert to anon, authenticated
with check (
  (user_id is null or user_id = auth.uid())
  and account_email is not null
  and position('@' in account_email) > 1
  and char_length(account_email) <= 254
  and char_length(topic) between 2 and 80
  and char_length(message) between 8 and 1800
);

drop policy if exists support_requests_admin_update on public.support_requests;
create policy support_requests_admin_update on public.support_requests
for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- -----------------------------
-- Grants
-- -----------------------------

grant usage on schema public to anon, authenticated;
grant select on public.reward_items to anon, authenticated;
grant select on public.profiles to authenticated;
grant select on public.redemption_requests to authenticated;
grant select on public.coin_adjustments to authenticated;
grant select on public.admin_users to authenticated;
grant select on public.linked_services to authenticated;
grant insert on public.support_requests to anon;
grant select, insert on public.support_requests to authenticated;
grant insert, update on public.reward_items to authenticated;
grant update on public.support_requests to authenticated;
grant usage, select on public.support_requests_id_seq to anon;
grant usage, select on all sequences in schema public to authenticated;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.get_admin_role() to authenticated;
grant execute on function public.is_owner() to authenticated;
grant execute on function public.ensure_skinquest_profile() to authenticated;
grant execute on function public.save_skinquest_trade_url(text) to authenticated;
grant execute on function public.save_account_settings(boolean, boolean, boolean) to authenticated;
grant execute on function public.claim_level_rewards() to authenticated;
grant execute on function public.redeem_reward(bigint) to authenticated;
grant execute on function public.owner_set_admin_role(text, text) to authenticated;
grant execute on function public.admin_adjust_user_coins(text, integer, text) to authenticated;
grant execute on function public.admin_update_redemption_status(bigint, text, text, text) to authenticated;

-- -----------------------------
-- Admin setup step
-- -----------------------------
-- After your owner account has signed up, copy its auth.users id and run:
-- insert into public.admin_users (user_id, role)
-- values ('YOUR-USER-ID-HERE', 'owner')
-- on conflict (user_id) do update set role = excluded.role;
