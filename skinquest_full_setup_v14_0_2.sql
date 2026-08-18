-- SkinQuest full Supabase setup v14.0.2
-- No database changes were added beyond v14.0.1 in this release.
-- This full setup remains complete for brand-new Supabase projects.
-- Run this in Supabase SQL Editor only when setting up a fresh project.
-- Stable full setup including BitLabs accounting and the refund XP repair.

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
alter table public.reward_items add column if not exists max_per_user integer;

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
alter table public.redemption_requests add column if not exists reward_id bigint references public.reward_items(id) on delete set null;
alter table public.redemption_requests add column if not exists points_cost integer not null default 0;
alter table public.redemption_requests add column if not exists steam_trade_url text;
alter table public.redemption_requests add column if not exists admin_note text;
alter table public.redemption_requests add column if not exists trade_offer_url text;
alter table public.redemption_requests add column if not exists refunded_at timestamptz;
alter table public.redemption_requests add column if not exists completed_at timestamptz;
alter table public.redemption_requests add column if not exists updated_at timestamptz not null default now();
alter table public.redemption_requests add column if not exists admin_notified_at timestamptz;
alter table public.redemption_requests add column if not exists user_notified_at timestamptz;

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

create table if not exists public.support_rate_limits (
  key_hash text not null,
  window_start timestamptz not null,
  request_count integer not null default 0,
  primary key (key_hash, window_start)
);
alter table public.support_requests add column if not exists admin_note text;
alter table public.support_requests add column if not exists updated_at timestamptz not null default now();

-- v12.1.2: goal rewards (star up to 5 rewards to track on the dashboard).
create table if not exists public.favorite_rewards (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_id bigint not null references public.reward_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_id, reward_id)
);

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
create index if not exists favorite_rewards_user_idx on public.favorite_rewards(user_id, created_at desc);
create index if not exists favorite_rewards_reward_idx on public.favorite_rewards(reward_id);

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

-- v12.1.2: cap goal rewards (favorite_rewards) at 5 per user.
create or replace function public.enforce_favorite_reward_limit()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.favorite_rewards where user_id = new.user_id) >= 6 then
    raise exception 'You can only star up to 6 rewards as goals.';
  end if;
  return new;
end;
$$;

drop trigger if exists favorite_rewards_limit_trg on public.favorite_rewards;
create trigger favorite_rewards_limit_trg
before insert on public.favorite_rewards
for each row execute function public.enforce_favorite_reward_limit();

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

  if v_trade_url is not null and (
    v_trade_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?' or
    v_trade_url !~ '(^|[?&])partner=[0-9]+(&|$)' or
    v_trade_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)'
  ) then
    raise exception 'Invalid Steam trade URL.';
  end if;

  update public.profiles
  set steam_trade_url = v_trade_url,
      updated_at = now()
  where id = v_user_id
  returning * into v_profile;

  if v_profile.id is null then
    raise exception 'Could not find or create your profile.';
  end if;

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
    and lower(coalesce(source_type, '')) <> 'redemption_refund'
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
  v_user_redemptions integer;
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

  if v_reward.max_per_user is not null then
    select count(*) into v_user_redemptions
    from public.redemption_requests
    where user_id = v_user_id
      and reward_id = v_reward.id
      and status not in ('rejected', 'refunded', 'cancelled');
    if v_user_redemptions >= v_reward.max_per_user then
      raise exception 'You have reached the redemption limit for this reward.';
    end if;
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
alter table public.favorite_rewards enable row level security;

drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin on public.profiles
for select to authenticated
using (id = auth.uid() or public.is_admin());

drop policy if exists profiles_update_own_trade_url on public.profiles;
create policy profiles_update_own_trade_url on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

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

drop policy if exists favorite_rewards_select_own on public.favorite_rewards;
create policy favorite_rewards_select_own on public.favorite_rewards
for select to authenticated
using (user_id = auth.uid());

drop policy if exists favorite_rewards_insert_own on public.favorite_rewards;
create policy favorite_rewards_insert_own on public.favorite_rewards
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists favorite_rewards_delete_own on public.favorite_rewards;
create policy favorite_rewards_delete_own on public.favorite_rewards
for delete to authenticated
using (user_id = auth.uid());


-- -----------------------------
-- Admin notification subscriber views
-- -----------------------------
-- These views let owner/admin accounts quickly see the contact emails that opted into each notification category.
-- They use auth.users.email as the real email source and fall back to profiles.username only if it looks like an email.
-- Non-admin signed-in users receive zero rows because every view is gated by public.is_admin().

drop view if exists public.admin_notification_reward_update_emails;
drop view if exists public.admin_notification_offer_issue_emails;
drop view if exists public.admin_notification_product_update_emails;
drop view if exists public.admin_notification_subscribers;

create or replace view public.admin_notification_subscribers as
select
  p.id as user_id,
  coalesce(u.email, case when p.username like '%@%' then p.username else null end) as email,
  p.username,
  p.steam_id,
  p.steam_name,
  coalesce(p.notification_reward_updates, true) as reward_updates,
  coalesce(p.notification_offer_issues, true) as offer_issues,
  coalesce(p.notification_product_updates, false) as product_updates,
  p.account_status,
  p.created_at,
  p.updated_at,
  u.email_confirmed_at,
  u.last_sign_in_at
from public.profiles p
left join auth.users u on u.id = p.id
where public.is_admin();

create or replace view public.admin_notification_reward_update_emails as
select *
from public.admin_notification_subscribers
where reward_updates = true
  and email is not null;

create or replace view public.admin_notification_offer_issue_emails as
select *
from public.admin_notification_subscribers
where offer_issues = true
  and email is not null;

create or replace view public.admin_notification_product_update_emails as
select *
from public.admin_notification_subscribers
where product_updates = true
  and email is not null;

-- -----------------------------
-- Grants
-- -----------------------------

grant usage on schema public to anon, authenticated;
grant select on public.reward_items to anon, authenticated;
grant select on public.profiles to authenticated;
revoke update (steam_trade_url) on public.profiles from authenticated;
grant select on public.redemption_requests to authenticated;
grant select on public.coin_adjustments to authenticated;
grant select on public.admin_users to authenticated;
grant select on public.admin_notification_subscribers to authenticated;
grant select on public.admin_notification_reward_update_emails to authenticated;
grant select on public.admin_notification_offer_issue_emails to authenticated;
grant select on public.admin_notification_product_update_emails to authenticated;
grant select on public.linked_services to authenticated;
grant insert on public.support_requests to anon;
grant select, insert on public.support_requests to authenticated;
grant insert, update on public.reward_items to authenticated;
grant update on public.support_requests to authenticated;
grant select, insert, delete on public.favorite_rewards to authenticated;
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

-- v13 survey accounting. Edge Functions call this with the service-role JWT.
create or replace function public.process_offerwall_postback(
  p_provider text,
  p_event_id text,
  p_user_id uuid,
  p_amount integer,
  p_status text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.offerwall_events%rowtype;
  v_previous text;
  v_balance integer;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required.'; end if;
  p_provider := lower(trim(p_provider));
  p_status := lower(trim(p_status));
  if p_provider not in ('cpx', 'bitlabs', 'lootably') then raise exception 'Unsupported provider.'; end if;
  if p_event_id is null or char_length(p_event_id) > 180 then raise exception 'Invalid event id.'; end if;
  if p_amount < 0 or p_amount > 100000 then raise exception 'Invalid coin amount.'; end if;
  if p_status not in ('pending', 'completed', 'reversed', 'rejected') then raise exception 'Invalid status.'; end if;

  perform 1 from auth.users where id = p_user_id;
  if not found then raise exception 'Unknown user.'; end if;

  select * into v_event from public.offerwall_events
  where provider = p_provider and provider_event_id = p_event_id for update;
  if not found then
    insert into public.offerwall_events(provider, provider_event_id, user_id, amount, status, raw_payload, processed_at)
    values (p_provider, p_event_id, p_user_id, p_amount, 'pending', coalesce(p_payload, '{}'::jsonb), now())
    returning * into v_event;
  elsif v_event.user_id is distinct from p_user_id or v_event.amount is distinct from p_amount then
    raise exception 'Postback does not match the original event.';
  end if;

  v_previous := v_event.status;
  if p_status = 'completed' and v_previous <> 'completed' then
    insert into public.profiles(id, username) values (p_user_id, 'user') on conflict (id) do nothing;
    update public.profiles set points_balance = coalesce(points_balance, 0) + p_amount where id = p_user_id;
    insert into public.coin_adjustments(user_id, amount, reason, source_type, source_id, metadata)
    values (p_user_id, p_amount, initcap(p_provider) || ' survey completion', 'offerwall_credit', p_provider || ':' || p_event_id, jsonb_build_object('provider', p_provider));
  elsif p_status in ('reversed', 'rejected') and v_previous = 'completed' then
    select coalesce(points_balance, 0) into v_balance from public.profiles where id = p_user_id for update;
    update public.profiles
      set points_balance = greatest(0, coalesce(points_balance, 0) - p_amount),
          account_status = case when coalesce(v_balance, 0) < p_amount then 'under_review' else account_status end
      where id = p_user_id;
    insert into public.coin_adjustments(user_id, amount, reason, source_type, source_id, metadata)
    values (p_user_id, -p_amount, initcap(p_provider) || ' survey reversal', 'offerwall_reversal', p_provider || ':' || p_event_id, jsonb_build_object('provider', p_provider));
  end if;

  update public.offerwall_events set status = p_status, raw_payload = coalesce(p_payload, raw_payload), processed_at = now()
  where id = v_event.id;
  return jsonb_build_object('ok', true, 'event_id', v_event.id, 'previous_status', v_previous, 'status', p_status);
end;
$$;

revoke all on function public.process_offerwall_postback(text, text, uuid, integer, text, jsonb) from public, anon, authenticated;
grant execute on function public.process_offerwall_postback(text, text, uuid, integer, text, jsonb) to service_role;

create or replace function public.process_bitlabs_callback(
  p_event_id text,
  p_user_id uuid,
  p_amount integer,
  p_reference_id text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_id bigint;
  v_balance integer;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required.'; end if;
  p_event_id := trim(coalesce(p_event_id, ''));
  if p_event_id = '' or char_length(p_event_id) > 180 then raise exception 'Invalid event id.'; end if;
  if p_amount = 0 or p_amount < -100000 or p_amount > 100000 then raise exception 'Invalid coin amount.'; end if;
  perform 1 from auth.users where id = p_user_id;
  if not found then raise exception 'Unknown user.'; end if;

  insert into public.offerwall_events(provider, provider_event_id, user_id, amount, status, raw_payload, processed_at)
  values (
    'bitlabs', p_event_id, p_user_id, p_amount,
    case when p_amount > 0 then 'completed' else 'reversed' end,
    coalesce(p_payload, '{}'::jsonb), now()
  ) on conflict (provider, provider_event_id) do nothing
  returning id into v_event_id;
  if v_event_id is null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'event_id', p_event_id);
  end if;

  insert into public.profiles(id, username) values (p_user_id, 'user') on conflict (id) do nothing;
  select coalesce(points_balance, 0) into v_balance from public.profiles where id = p_user_id for update;
  update public.profiles
    set points_balance = greatest(0, coalesce(points_balance, 0) + p_amount),
        account_status = case
          when p_amount < 0 and coalesce(v_balance, 0) < (p_amount * -1) then 'under_review'
          else account_status
        end
    where id = p_user_id;

  insert into public.coin_adjustments(user_id, amount, reason, source_type, source_id, metadata)
  values (
    p_user_id, p_amount,
    case when p_amount > 0 then 'BitLabs survey completion' else 'BitLabs survey reconciliation' end,
    case when p_amount > 0 then 'offerwall_credit' else 'offerwall_reversal' end,
    'bitlabs:' || p_event_id,
    jsonb_build_object('provider', 'bitlabs', 'reference_id', p_reference_id)
  );
  return jsonb_build_object('ok', true, 'duplicate', false, 'event_id', p_event_id, 'amount', p_amount);
end;
$$;

revoke all on function public.process_bitlabs_callback(text, uuid, integer, text, jsonb) from public, anon, authenticated;
grant execute on function public.process_bitlabs_callback(text, uuid, integer, text, jsonb) to service_role;

-- Support must go through the rate-limited Edge Function.
drop policy if exists support_requests_insert_own on public.support_requests;
drop policy if exists support_requests_insert_contact on public.support_requests;
revoke insert on public.support_requests from anon, authenticated;
revoke usage, select on public.support_requests_id_seq from anon;
drop policy if exists profiles_update_own_trade_url on public.profiles;
revoke update (steam_trade_url) on public.profiles from authenticated;

alter table public.support_rate_limits enable row level security;
revoke all on public.support_rate_limits from public, anon, authenticated;

-- Disable an accidental test price and repair the public item spelling.
update public.reward_items set active = false where lower(name) = 'galil ar | blue titanium' and coalesce(nullif(points_coins, 0), points_cost, 0) <= 1;
update public.reward_items set name = replace(name, 'Dreams & Nightmare Case', 'Dreams & Nightmares Case') where name like '%Dreams & Nightmare Case%';

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'redemption_trade_offer_url_safe') then
    alter table public.redemption_requests add constraint redemption_trade_offer_url_safe
      check (trade_offer_url is null or trade_offer_url ~* '^https://(www\.)?steamcommunity\.com/tradeoffer/') not valid;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_steam_trade_url_safe') then
    alter table public.profiles add constraint profiles_steam_trade_url_safe
      check (steam_trade_url is null or steam_trade_url ~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?.*partner=[0-9]+.*token=[A-Za-z0-9_-]+') not valid;
  end if;
end $$;

-- -----------------------------
-- Admin setup step
-- -----------------------------
-- After your owner account has signed up, copy its auth.users id and run:
-- insert into public.admin_users (user_id, role)
-- values ('YOUR-USER-ID-HERE', 'owner')
-- on conflict (user_id) do update set role = excluded.role;

-- Refresh the Supabase API function cache after setup.
notify pgrst, 'reload schema';


-- ============================================================================
-- SkinQuest v14.0.2 product layer (included in full fresh-project setup)
-- Everything below is also contained in skinquest_upgrade_existing_to_v14_0_2.sql.
-- Do NOT separately run the upgrade file after using this full setup on a new project.
-- ============================================================================


begin;

-- Fail early with a clear message if this is not the expected existing SkinQuest database.
do $$
begin
  if to_regclass('public.profiles') is null
     or to_regclass('public.admin_users') is null
     or to_regclass('public.reward_items') is null
     or to_regclass('public.redemption_requests') is null
     or to_regclass('public.coin_adjustments') is null
     or to_regclass('public.favorite_rewards') is null then
    raise exception 'SkinQuest v14 upgrade requires the existing v13.1.0 database schema. Use skinquest_full_setup_v14_0_2.sql only for a NEW empty Supabase project.';
  end if;
end $$;

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- 0. Shared helper: current user is a SkinQuest admin
-- -----------------------------------------------------------------------------
create or replace function public.sq_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and exists (
       select 1
       from public.admin_users au
       where au.user_id = auth.uid()
     );
$$;

revoke all on function public.sq_is_admin() from public;
grant execute on function public.sq_is_admin() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 1. Activity streaks
-- -----------------------------------------------------------------------------
create table if not exists public.sq_user_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0 check (current_streak >= 0),
  longest_streak integer not null default 0 check (longest_streak >= 0),
  last_active_date date,
  updated_at timestamptz not null default now()
);

create table if not exists public.sq_daily_activity (
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  page_views integer not null default 1 check (page_views >= 1),
  primary key (user_id, activity_date)
);

-- -----------------------------------------------------------------------------
-- 2. Quests + achievements (non-economic; no client can mint coins)
-- -----------------------------------------------------------------------------
create table if not exists public.sq_quests (
  quest_key text primary key,
  title text not null,
  description text not null,
  category text not null default 'progress',
  target integer not null default 1 check (target > 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.sq_user_quest_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  quest_key text not null references public.sq_quests(quest_key) on delete cascade,
  progress integer not null default 0 check (progress >= 0),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, quest_key)
);

create table if not exists public.sq_achievements (
  achievement_key text primary key,
  title text not null,
  description text not null,
  icon text not null default '★',
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.sq_user_achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_key text not null references public.sq_achievements(achievement_key) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, achievement_key)
);

insert into public.sq_quests (quest_key, title, description, category, target, sort_order, active)
values
  ('add_trade_url', 'Ready to trade', 'Save a valid Steam trade URL.', 'setup', 1, 10, true),
  ('star_goal', 'Pick your target', 'Star a reward you want to save for.', 'setup', 1, 20, true),
  ('first_earn', 'First earnings', 'Earn your first verified SkinQuest coins.', 'earning', 1, 30, true),
  ('earn_250', 'Getting started', 'Earn 250 verified coins in total.', 'earning', 250, 40, true),
  ('earn_1000', 'Four figures', 'Earn 1,000 verified coins in total.', 'earning', 1000, 50, true),
  ('first_redeem', 'First reward', 'Submit your first reward redemption.', 'rewards', 1, 60, true),
  ('five_completed', 'Collector', 'Complete five reward redemptions.', 'rewards', 5, 70, true),
  ('streak_3', 'Three-day run', 'Visit SkinQuest on three consecutive UTC days.', 'activity', 3, 80, true),
  ('streak_7', 'Weekly regular', 'Visit SkinQuest on seven consecutive UTC days.', 'activity', 7, 90, true)
on conflict (quest_key) do update set
  title = excluded.title,
  description = excluded.description,
  category = excluded.category,
  target = excluded.target,
  sort_order = excluded.sort_order,
  active = excluded.active;

insert into public.sq_achievements (achievement_key, title, description, icon, sort_order, active)
values
  ('first_earn', 'First Blood', 'Earned verified coins for the first time.', '+', 10, true),
  ('goal_set', 'Target Acquired', 'Starred a reward as a goal.', '★', 20, true),
  ('first_redeem', 'Loadout Started', 'Submitted the first reward redemption.', '◆', 30, true),
  ('first_completed', 'Delivered', 'Completed the first reward redemption.', '✓', 40, true),
  ('collector_5', 'Collector', 'Completed five reward redemptions.', '5', 50, true),
  ('earned_1000', 'Four Figures', 'Earned at least 1,000 verified coins.', '1K', 60, true),
  ('streak_3', 'On A Run', 'Reached a three-day activity streak.', '3', 70, true),
  ('streak_7', 'Weekly Regular', 'Reached a seven-day activity streak.', '7', 80, true)
on conflict (achievement_key) do update set
  title = excluded.title,
  description = excluded.description,
  icon = excluded.icon,
  sort_order = excluded.sort_order,
  active = excluded.active;

-- -----------------------------------------------------------------------------
-- 3. In-app notifications
-- -----------------------------------------------------------------------------
create table if not exists public.sq_notifications (
  id bigint generated by default as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null default 'info',
  title text not null,
  body text,
  href text,
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists sq_notifications_user_unread_idx
  on public.sq_notifications (user_id, created_at desc)
  where read_at is null;

create index if not exists sq_notifications_user_created_idx
  on public.sq_notifications (user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- 4. Reward restock subscriptions
-- -----------------------------------------------------------------------------
create table if not exists public.sq_reward_stock_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_id bigint not null references public.reward_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, reward_id)
);

-- -----------------------------------------------------------------------------
-- 5. Promo codes for QR cards / social campaigns
-- -----------------------------------------------------------------------------
create table if not exists public.sq_promo_codes (
  id bigint generated by default as identity primary key,
  code text not null unique,
  campaign text,
  coin_amount integer not null default 1 check (coin_amount >= 0),
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  redemptions_count integer not null default 0 check (redemptions_count >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (length(btrim(code)) between 3 and 64),
  check (coin_amount > 0)
);

create table if not exists public.sq_promo_redemptions (
  promo_code_id bigint not null references public.sq_promo_codes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  coins_awarded integer not null check (coins_awarded >= 0),
  redeemed_at timestamptz not null default now(),
  primary key (promo_code_id, user_id)
);

create index if not exists sq_promo_codes_active_idx
  on public.sq_promo_codes (active, starts_at, ends_at);

-- -----------------------------------------------------------------------------
-- 6. Referral attribution. No automatic signup payout.
-- -----------------------------------------------------------------------------
create table if not exists public.sq_referral_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  code text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.sq_referrals (
  referred_user_id uuid primary key references auth.users(id) on delete cascade,
  referrer_user_id uuid not null references auth.users(id) on delete cascade,
  referral_code text not null,
  joined_at timestamptz not null default now(),
  qualified_at timestamptz,
  reward_issued_at timestamptz,
  qualification_reference text,
  check (referred_user_id <> referrer_user_id)
);

create index if not exists sq_referrals_referrer_idx
  on public.sq_referrals (referrer_user_id, joined_at desc);

-- -----------------------------------------------------------------------------
-- 7. First-touch acquisition attribution + product funnel events
-- -----------------------------------------------------------------------------
create table if not exists public.sq_acquisition (
  user_id uuid primary key references auth.users(id) on delete cascade,
  source text,
  medium text,
  campaign text,
  content text,
  term text,
  landing_path text,
  referrer text,
  referral_code text,
  promo_code text,
  captured_at timestamptz not null default now()
);

create table if not exists public.sq_product_events (
  id bigint generated by default as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_name text not null,
  page_path text,
  properties jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (length(event_name) between 1 and 64),
  check (octet_length(properties::text) <= 8192)
);

create index if not exists sq_product_events_user_idx
  on public.sq_product_events (user_id, created_at desc);
create index if not exists sq_product_events_name_idx
  on public.sq_product_events (event_name, created_at desc);

-- -----------------------------------------------------------------------------
-- 8. Public status + admin audit
-- -----------------------------------------------------------------------------
create table if not exists public.sq_system_status (
  component text primary key,
  display_name text not null,
  status text not null default 'operational' check (status in ('operational','degraded','maintenance','incident')),
  message text,
  sort_order integer not null default 0,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.sq_system_status (component, display_name, status, message, sort_order)
values
  ('platform', 'SkinQuest', 'operational', 'Platform available', 10),
  ('earning', 'Earning providers', 'operational', 'Connected providers available', 20),
  ('rewards', 'Reward fulfillment', 'operational', 'Manual reward review available', 30)
on conflict (component) do nothing;

create table if not exists public.sq_admin_audit_log (
  id bigint generated by default as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists sq_admin_audit_created_idx
  on public.sq_admin_audit_log (created_at desc);

-- -----------------------------------------------------------------------------
-- 9. RLS
-- -----------------------------------------------------------------------------
alter table public.sq_user_streaks enable row level security;
alter table public.sq_daily_activity enable row level security;
alter table public.sq_quests enable row level security;
alter table public.sq_user_quest_progress enable row level security;
alter table public.sq_achievements enable row level security;
alter table public.sq_user_achievements enable row level security;
alter table public.sq_notifications enable row level security;
alter table public.sq_reward_stock_subscriptions enable row level security;
alter table public.sq_promo_codes enable row level security;
alter table public.sq_promo_redemptions enable row level security;
alter table public.sq_referral_codes enable row level security;
alter table public.sq_referrals enable row level security;
alter table public.sq_acquisition enable row level security;
alter table public.sq_product_events enable row level security;
alter table public.sq_system_status enable row level security;
alter table public.sq_admin_audit_log enable row level security;

-- Drop only policies owned by this migration, so re-running is safe.
drop policy if exists "sq own streak" on public.sq_user_streaks;
drop policy if exists "sq own daily activity" on public.sq_daily_activity;
drop policy if exists "sq quests public read" on public.sq_quests;
drop policy if exists "sq own quest progress" on public.sq_user_quest_progress;
drop policy if exists "sq achievements public read" on public.sq_achievements;
drop policy if exists "sq own achievements" on public.sq_user_achievements;
drop policy if exists "sq own notifications read" on public.sq_notifications;
drop policy if exists "sq own notifications update" on public.sq_notifications;
drop policy if exists "sq own stock subscriptions" on public.sq_reward_stock_subscriptions;
drop policy if exists "sq promo admins only" on public.sq_promo_codes;
drop policy if exists "sq own promo redemptions" on public.sq_promo_redemptions;
drop policy if exists "sq own referral code" on public.sq_referral_codes;
drop policy if exists "sq referral participants read" on public.sq_referrals;
drop policy if exists "sq own acquisition" on public.sq_acquisition;
drop policy if exists "sq own product events" on public.sq_product_events;
drop policy if exists "sq status public read" on public.sq_system_status;
drop policy if exists "sq status admin write" on public.sq_system_status;
drop policy if exists "sq audit admin read" on public.sq_admin_audit_log;

create policy "sq own streak"
on public.sq_user_streaks for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq own daily activity"
on public.sq_daily_activity for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq quests public read"
on public.sq_quests for select
using (active = true or public.sq_is_admin());

create policy "sq own quest progress"
on public.sq_user_quest_progress for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq achievements public read"
on public.sq_achievements for select
using (active = true or public.sq_is_admin());

create policy "sq own achievements"
on public.sq_user_achievements for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq own notifications read"
on public.sq_notifications for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq own notifications update"
on public.sq_notifications for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "sq own stock subscriptions"
on public.sq_reward_stock_subscriptions for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "sq promo admins only"
on public.sq_promo_codes for all
using (public.sq_is_admin())
with check (public.sq_is_admin());

create policy "sq own promo redemptions"
on public.sq_promo_redemptions for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq own referral code"
on public.sq_referral_codes for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq referral participants read"
on public.sq_referrals for select
using (auth.uid() = referred_user_id or auth.uid() = referrer_user_id or public.sq_is_admin());

create policy "sq own acquisition"
on public.sq_acquisition for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq own product events"
on public.sq_product_events for select
using (auth.uid() = user_id or public.sq_is_admin());

create policy "sq status public read"
on public.sq_system_status for select
using (true);

create policy "sq status admin write"
on public.sq_system_status for all
using (public.sq_is_admin())
with check (public.sq_is_admin());

create policy "sq audit admin read"
on public.sq_admin_audit_log for select
using (public.sq_is_admin());

-- Do not expose direct writes to trusted-generated tables.
revoke insert, update, delete on public.sq_user_streaks from anon, authenticated;
revoke insert, update, delete on public.sq_daily_activity from anon, authenticated;
revoke insert, update, delete on public.sq_user_quest_progress from anon, authenticated;
revoke insert, update, delete on public.sq_user_achievements from anon, authenticated;
revoke insert, delete on public.sq_notifications from anon, authenticated;
revoke insert, update, delete on public.sq_promo_redemptions from anon, authenticated;
revoke insert, update, delete on public.sq_referral_codes from anon, authenticated;
revoke insert, update, delete on public.sq_referrals from anon, authenticated;
revoke insert, update, delete on public.sq_acquisition from anon, authenticated;
revoke insert, update, delete on public.sq_product_events from anon, authenticated;
revoke insert, update, delete on public.sq_admin_audit_log from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 10. Utility: verified earned coins (excludes SkinQuest-created bonuses)
-- -----------------------------------------------------------------------------
create or replace function public.sq_verified_earned_coins(p_user_id uuid)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(ca.amount), 0)::bigint
  from public.coin_adjustments ca
  where ca.user_id = p_user_id
    and ca.amount > 0
    and lower(coalesce(ca.reason, '')) not like 'level reward%'
    and lower(coalesce(ca.reason, '')) not like 'promo code%'
    and lower(coalesce(ca.reason, '')) not like 'referral reward%'
    and lower(coalesce(ca.reason, '')) not like 'manual admin%';
$$;

revoke all on function public.sq_verified_earned_coins(uuid) from public, anon, authenticated;
grant execute on function public.sq_verified_earned_coins(uuid) to service_role;

-- -----------------------------------------------------------------------------
-- 11. Internal progress refresh
-- -----------------------------------------------------------------------------
create or replace function public.sq_refresh_progress_for(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_earned bigint := 0;
  v_favorites integer := 0;
  v_requests integer := 0;
  v_completed integer := 0;
  v_has_trade integer := 0;
  v_streak integer := 0;
  r record;
  v_progress integer;
begin
  if p_user_id is null then return; end if;

  v_earned := public.sq_verified_earned_coins(p_user_id);

  select count(*)::integer into v_favorites
  from public.favorite_rewards
  where user_id = p_user_id;

  select count(*)::integer,
         count(*) filter (where status = 'completed')::integer
    into v_requests, v_completed
  from public.redemption_requests
  where user_id = p_user_id;

  select case when coalesce(steam_trade_url, '') <> '' then 1 else 0 end
    into v_has_trade
  from public.profiles
  where id = p_user_id;
  v_has_trade := coalesce(v_has_trade, 0);

  select coalesce(current_streak, 0)
    into v_streak
  from public.sq_user_streaks
  where user_id = p_user_id;
  v_streak := coalesce(v_streak, 0);

  for r in
    select quest_key, target
    from public.sq_quests
    where active = true
  loop
    v_progress := case r.quest_key
      when 'add_trade_url' then v_has_trade
      when 'star_goal' then least(v_favorites, r.target)
      when 'first_earn' then case when v_earned > 0 then 1 else 0 end
      when 'earn_250' then least(v_earned, r.target)::integer
      when 'earn_1000' then least(v_earned, r.target)::integer
      when 'first_redeem' then least(v_requests, r.target)
      when 'five_completed' then least(v_completed, r.target)
      when 'streak_3' then least(v_streak, r.target)
      when 'streak_7' then least(v_streak, r.target)
      else 0
    end;

    insert into public.sq_user_quest_progress (user_id, quest_key, progress, completed_at, updated_at)
    values (
      p_user_id,
      r.quest_key,
      greatest(v_progress, 0),
      case when v_progress >= r.target then now() else null end,
      now()
    )
    on conflict (user_id, quest_key) do update set
      progress = greatest(public.sq_user_quest_progress.progress, excluded.progress),
      completed_at = case
        when public.sq_user_quest_progress.completed_at is not null then public.sq_user_quest_progress.completed_at
        when excluded.progress >= r.target then now()
        else null
      end,
      updated_at = now();
  end loop;

  -- Achievements are derived only from trusted database state.
  if v_earned > 0 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'first_earn') on conflict do nothing;
  end if;

  if v_favorites > 0 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'goal_set') on conflict do nothing;
  end if;

  if v_requests > 0 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'first_redeem') on conflict do nothing;
  end if;

  if v_completed > 0 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'first_completed') on conflict do nothing;
  end if;

  if v_completed >= 5 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'collector_5') on conflict do nothing;
  end if;

  if v_earned >= 1000 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'earned_1000') on conflict do nothing;
  end if;

  if v_streak >= 3 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'streak_3') on conflict do nothing;
  end if;

  if v_streak >= 7 then
    insert into public.sq_user_achievements(user_id, achievement_key)
    values (p_user_id, 'streak_7') on conflict do nothing;
  end if;
end;
$$;

revoke all on function public.sq_refresh_progress_for(uuid) from public, anon, authenticated;
grant execute on function public.sq_refresh_progress_for(uuid) to service_role;

create or replace function public.sq_refresh_my_progress()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_completed integer;
  v_total integer;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;
  perform public.sq_refresh_progress_for(v_user);

  select count(*) filter (where p.completed_at is not null)::integer,
         count(*)::integer
  into v_completed, v_total
  from public.sq_user_quest_progress p
  join public.sq_quests q on q.quest_key = p.quest_key
  where p.user_id = v_user and q.active = true;

  return jsonb_build_object('ok', true, 'completed', coalesce(v_completed,0), 'total', coalesce(v_total,0));
end;
$$;

revoke all on function public.sq_refresh_my_progress() from public;
grant execute on function public.sq_refresh_my_progress() to authenticated;

-- -----------------------------------------------------------------------------
-- 12. Record a daily visit + streak
-- -----------------------------------------------------------------------------
create or replace function public.sq_record_activity()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_today date := (now() at time zone 'UTC')::date;
  v_row public.sq_user_streaks%rowtype;
  v_current integer;
  v_longest integer;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;

  insert into public.sq_daily_activity(user_id, activity_date, first_seen_at, last_seen_at, page_views)
  values(v_user, v_today, now(), now(), 1)
  on conflict(user_id, activity_date) do update
    set last_seen_at = now(),
        page_views = public.sq_daily_activity.page_views + 1;

  select * into v_row
  from public.sq_user_streaks
  where user_id = v_user
  for update;

  if not found then
    v_current := 1;
    v_longest := 1;
    insert into public.sq_user_streaks(user_id, current_streak, longest_streak, last_active_date, updated_at)
    values(v_user, 1, 1, v_today, now());
  elsif v_row.last_active_date = v_today then
    v_current := v_row.current_streak;
    v_longest := v_row.longest_streak;
    update public.sq_user_streaks set updated_at = now() where user_id = v_user;
  elsif v_row.last_active_date = v_today - 1 then
    v_current := v_row.current_streak + 1;
    v_longest := greatest(v_row.longest_streak, v_current);
    update public.sq_user_streaks
      set current_streak = v_current,
          longest_streak = v_longest,
          last_active_date = v_today,
          updated_at = now()
    where user_id = v_user;
  else
    v_current := 1;
    v_longest := greatest(v_row.longest_streak, 1);
    update public.sq_user_streaks
      set current_streak = 1,
          longest_streak = v_longest,
          last_active_date = v_today,
          updated_at = now()
    where user_id = v_user;
  end if;

  perform public.sq_refresh_progress_for(v_user);

  return jsonb_build_object(
    'ok', true,
    'current_streak', v_current,
    'longest_streak', v_longest,
    'date', v_today
  );
end;
$$;

revoke all on function public.sq_record_activity() from public;
grant execute on function public.sq_record_activity() to authenticated;

-- -----------------------------------------------------------------------------
-- 13. Notification RPCs
-- -----------------------------------------------------------------------------
create or replace function public.sq_mark_notification_read(p_notification_id bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  update public.sq_notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id and user_id = auth.uid();
  return found;
end;
$$;

create or replace function public.sq_mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in required.'; end if;
  update public.sq_notifications
  set read_at = now()
  where user_id = auth.uid() and read_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.sq_mark_notification_read(bigint) from public;
revoke all on function public.sq_mark_all_notifications_read() from public;
grant execute on function public.sq_mark_notification_read(bigint) to authenticated;
grant execute on function public.sq_mark_all_notifications_read() to authenticated;

-- -----------------------------------------------------------------------------
-- 14. Reward restock subscribe/unsubscribe
-- -----------------------------------------------------------------------------
create or replace function public.sq_toggle_stock_alert(p_reward_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_exists boolean;
  v_reward_name text;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;

  select name into v_reward_name from public.reward_items where id = p_reward_id;
  if v_reward_name is null then raise exception 'Reward not found.'; end if;

  select exists(
    select 1 from public.sq_reward_stock_subscriptions
    where user_id = v_user and reward_id = p_reward_id
  ) into v_exists;

  if v_exists then
    delete from public.sq_reward_stock_subscriptions
    where user_id = v_user and reward_id = p_reward_id;
    return jsonb_build_object('subscribed', false, 'reward_name', v_reward_name);
  end if;

  insert into public.sq_reward_stock_subscriptions(user_id, reward_id)
  values(v_user, p_reward_id)
  on conflict do nothing;
  return jsonb_build_object('subscribed', true, 'reward_name', v_reward_name);
end;
$$;

revoke all on function public.sq_toggle_stock_alert(bigint) from public;
grant execute on function public.sq_toggle_stock_alert(bigint) to authenticated;

-- -----------------------------------------------------------------------------
-- 15. Promo code redemption + admin creation
-- -----------------------------------------------------------------------------
create or replace function public.sq_redeem_promo_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_promo public.sq_promo_codes%rowtype;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;
  if length(v_code) < 3 then raise exception 'Enter a valid code.'; end if;

  select * into v_promo
  from public.sq_promo_codes
  where upper(code) = v_code
  for update;

  if not found then raise exception 'That code does not exist.'; end if;
  if not v_promo.active then raise exception 'That code is inactive.'; end if;
  if v_promo.starts_at is not null and now() < v_promo.starts_at then raise exception 'That code is not active yet.'; end if;
  if v_promo.ends_at is not null and now() >= v_promo.ends_at then raise exception 'That code has expired.'; end if;
  if v_promo.max_redemptions is not null and v_promo.redemptions_count >= v_promo.max_redemptions then
    raise exception 'That code has reached its redemption limit.';
  end if;
  if exists(select 1 from public.sq_promo_redemptions where promo_code_id = v_promo.id and user_id = v_user) then
    raise exception 'You have already redeemed that code.';
  end if;

  perform 1 from public.profiles where id = v_user for update;
  if not found then raise exception 'Profile not found.'; end if;

  insert into public.sq_promo_redemptions(promo_code_id, user_id, coins_awarded)
  values(v_promo.id, v_user, v_promo.coin_amount);

  update public.sq_promo_codes
  set redemptions_count = redemptions_count + 1
  where id = v_promo.id;

  update public.profiles
  set points_balance = coalesce(points_balance, 0) + v_promo.coin_amount
  where id = v_user;

  insert into public.coin_adjustments(user_id, amount, reason)
  values(v_user, v_promo.coin_amount, 'Promo code: ' || v_promo.code);

  insert into public.sq_product_events(user_id, event_name, page_path, properties)
  values(v_user, 'promo_redeemed', null, jsonb_build_object('campaign', v_promo.campaign, 'coins', v_promo.coin_amount));

  return jsonb_build_object(
    'ok', true,
    'coins_awarded', v_promo.coin_amount,
    'campaign', v_promo.campaign
  );
end;
$$;

create or replace function public.sq_admin_create_promo_code(
  p_code text,
  p_coin_amount integer,
  p_campaign text default null,
  p_max_redemptions integer default null,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(regexp_replace(btrim(coalesce(p_code,'')), '[^A-Za-z0-9_-]+', '', 'g'));
  v_id bigint;
begin
  if not public.sq_is_admin() then raise exception 'Admin access required.'; end if;
  if length(v_code) < 3 then raise exception 'Code must contain at least 3 valid characters.'; end if;
  if p_coin_amount <= 0 or p_coin_amount > 100000 then raise exception 'Coin amount is outside the allowed range.'; end if;
  if p_max_redemptions is not null and p_max_redemptions <= 0 then raise exception 'Max redemptions must be positive.'; end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at <= p_starts_at then raise exception 'End must be after start.'; end if;

  insert into public.sq_promo_codes(code, campaign, coin_amount, max_redemptions, starts_at, ends_at, created_by)
  values(v_code, nullif(btrim(p_campaign),''), p_coin_amount, p_max_redemptions, p_starts_at, p_ends_at, auth.uid())
  returning id into v_id;

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values(auth.uid(), 'promo_create', 'promo_code', v_id::text, jsonb_build_object('code',v_code,'coins',p_coin_amount,'max',p_max_redemptions,'campaign',p_campaign));

  return jsonb_build_object('ok', true, 'id', v_id, 'code', v_code);
end;
$$;

revoke all on function public.sq_redeem_promo_code(text) from public;
revoke all on function public.sq_admin_create_promo_code(text,integer,text,integer,timestamptz,timestamptz) from public;
grant execute on function public.sq_redeem_promo_code(text) to authenticated;
grant execute on function public.sq_admin_create_promo_code(text,integer,text,integer,timestamptz,timestamptz) to authenticated;

-- -----------------------------------------------------------------------------
-- 16. Referral code RPCs
-- -----------------------------------------------------------------------------
create or replace function public.sq_get_or_create_referral_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text;
  i integer;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;

  select code into v_code from public.sq_referral_codes where user_id = v_user;
  if v_code is not null then return v_code; end if;

  for i in 1..12 loop
    v_code := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10));
    begin
      insert into public.sq_referral_codes(user_id, code) values(v_user, v_code);
      return v_code;
    exception when unique_violation then
      null;
    end;
  end loop;

  raise exception 'Could not generate referral code. Try again.';
end;
$$;

create or replace function public.sq_claim_referral_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(btrim(coalesce(p_code,'')));
  v_referrer uuid;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;
  if exists(select 1 from public.sq_referrals where referred_user_id = v_user) then
    return jsonb_build_object('ok', true, 'already_attributed', true);
  end if;

  select user_id into v_referrer
  from public.sq_referral_codes
  where upper(code) = v_code;

  if v_referrer is null then raise exception 'Referral code not found.'; end if;
  if v_referrer = v_user then raise exception 'You cannot refer yourself.'; end if;

  insert into public.sq_referrals(referred_user_id, referrer_user_id, referral_code)
  values(v_user, v_referrer, v_code)
  on conflict(referred_user_id) do nothing;

  return jsonb_build_object('ok', true, 'attributed', true);
end;
$$;

-- Call this from a trusted provider callback / Edge Function only after you decide a referral is qualified.
create or replace function public.sq_award_referral_conversion(
  p_referred_user_id uuid,
  p_qualification_reference text,
  p_referrer_coin_bonus integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ref public.sq_referrals%rowtype;
begin
  if auth.role() <> 'service_role' and not public.sq_is_admin() then
    raise exception 'Service role or admin required.';
  end if;
  if p_referrer_coin_bonus < 0 or p_referrer_coin_bonus > 100000 then raise exception 'Invalid referral bonus.'; end if;

  select * into v_ref
  from public.sq_referrals
  where referred_user_id = p_referred_user_id
  for update;

  if not found then return jsonb_build_object('ok', false, 'reason', 'no_referral'); end if;
  if v_ref.reward_issued_at is not null then return jsonb_build_object('ok', true, 'already_rewarded', true); end if;

  update public.sq_referrals
  set qualified_at = coalesce(qualified_at, now()),
      reward_issued_at = now(),
      qualification_reference = nullif(btrim(p_qualification_reference),'')
  where referred_user_id = p_referred_user_id;

  if p_referrer_coin_bonus > 0 then
    update public.profiles
    set points_balance = coalesce(points_balance,0) + p_referrer_coin_bonus
    where id = v_ref.referrer_user_id;

    insert into public.coin_adjustments(user_id, amount, reason)
    values(v_ref.referrer_user_id, p_referrer_coin_bonus, 'Referral reward');
  end if;

  insert into public.sq_notifications(user_id, notification_type, title, body, href)
  values(v_ref.referrer_user_id, 'referral', 'Referral qualified',
         case when p_referrer_coin_bonus > 0 then '+' || p_referrer_coin_bonus || ' coins were added to your wallet.' else 'One of your referrals qualified.' end,
         '/dashboard');

  return jsonb_build_object('ok', true, 'referrer_user_id', v_ref.referrer_user_id, 'coins_awarded', p_referrer_coin_bonus);
end;
$$;

revoke all on function public.sq_get_or_create_referral_code() from public;
revoke all on function public.sq_claim_referral_code(text) from public;
revoke all on function public.sq_award_referral_conversion(uuid,text,integer) from public, anon, authenticated;
grant execute on function public.sq_get_or_create_referral_code() to authenticated;
grant execute on function public.sq_claim_referral_code(text) to authenticated;
grant execute on function public.sq_award_referral_conversion(uuid,text,integer) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 17. First-touch attribution + safe product events
-- -----------------------------------------------------------------------------
create or replace function public.sq_set_acquisition(
  p_source text default null,
  p_medium text default null,
  p_campaign text default null,
  p_content text default null,
  p_term text default null,
  p_landing_path text default null,
  p_referrer text default null,
  p_referral_code text default null,
  p_promo_code text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Sign in required.'; end if;

  insert into public.sq_acquisition(user_id, source, medium, campaign, content, term, landing_path, referrer, referral_code, promo_code)
  values(
    v_user,
    left(nullif(btrim(p_source),''), 120),
    left(nullif(btrim(p_medium),''), 120),
    left(nullif(btrim(p_campaign),''), 160),
    left(nullif(btrim(p_content),''), 160),
    left(nullif(btrim(p_term),''), 160),
    left(nullif(btrim(p_landing_path),''), 500),
    left(nullif(btrim(p_referrer),''), 500),
    left(nullif(btrim(p_referral_code),''), 64),
    left(nullif(btrim(p_promo_code),''), 64)
  )
  on conflict(user_id) do nothing;

  return found;
end;
$$;

create or replace function public.sq_track_event(p_event_name text, p_page_path text default null, p_properties jsonb default '{}'::jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_event text := lower(btrim(coalesce(p_event_name,'')));
begin
  if v_user is null then return false; end if;
  if v_event !~ '^[a-z0-9_]{1,64}$' then raise exception 'Invalid event name.'; end if;
  if octet_length(coalesce(p_properties,'{}'::jsonb)::text) > 8192 then raise exception 'Event payload too large.'; end if;

  -- Analytics must never become a write-amplification vector.
  if (select count(*) from public.sq_product_events where user_id = v_user and created_at >= date_trunc('day', now())) >= 500 then
    return false;
  end if;

  insert into public.sq_product_events(user_id, event_name, page_path, properties)
  values(v_user, v_event, left(p_page_path, 500), coalesce(p_properties,'{}'::jsonb));
  return true;
end;
$$;

revoke all on function public.sq_set_acquisition(text,text,text,text,text,text,text,text,text) from public;
revoke all on function public.sq_track_event(text,text,jsonb) from public;
grant execute on function public.sq_set_acquisition(text,text,text,text,text,text,text,text,text) to authenticated;
grant execute on function public.sq_track_event(text,text,jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 18. Public, real trust data (no fake counters, no user identifiers)
-- -----------------------------------------------------------------------------
create or replace function public.sq_public_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'active_rewards', (select count(*) from public.reward_items where active = true),
    'completed_rewards', (select count(*) from public.redemption_requests where status = 'completed'),
    'open_rewards', (select count(*) from public.redemption_requests where status in ('pending','reviewing','trade_sent'))
  );
$$;

create or replace function public.sq_recent_completed_rewards(p_limit integer default 6)
returns table(reward_name text, completed_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select rr.reward_name,
         coalesce(rr.completed_at, rr.updated_at, rr.created_at) as completed_at
  from public.redemption_requests rr
  where rr.status = 'completed'
    and coalesce(rr.reward_name,'') <> ''
  order by coalesce(rr.completed_at, rr.updated_at, rr.created_at) desc
  limit least(greatest(coalesce(p_limit,6),1),12);
$$;

revoke all on function public.sq_public_stats() from public;
revoke all on function public.sq_recent_completed_rewards(integer) from public;
grant execute on function public.sq_public_stats() to anon, authenticated;
grant execute on function public.sq_recent_completed_rewards(integer) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- 19. User progression dashboard RPC
-- -----------------------------------------------------------------------------
create or replace function public.sq_get_my_growth_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_streak integer := 0;
  v_longest integer := 0;
  v_quests_done integer := 0;
  v_quests_total integer := 0;
  v_achievements integer := 0;
  v_referrals integer := 0;
  v_qualified integer := 0;
  v_unread integer := 0;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;
  perform public.sq_refresh_progress_for(v_user);

  select coalesce(current_streak,0), coalesce(longest_streak,0)
  into v_streak, v_longest
  from public.sq_user_streaks where user_id = v_user;

  select count(*) filter(where p.completed_at is not null)::integer, count(*)::integer
  into v_quests_done, v_quests_total
  from public.sq_quests q
  left join public.sq_user_quest_progress p
    on p.quest_key = q.quest_key and p.user_id = v_user
  where q.active = true;

  select count(*)::integer into v_achievements
  from public.sq_user_achievements where user_id = v_user;

  select count(*)::integer,
         count(*) filter(where qualified_at is not null)::integer
  into v_referrals, v_qualified
  from public.sq_referrals where referrer_user_id = v_user;

  select count(*)::integer into v_unread
  from public.sq_notifications where user_id = v_user and read_at is null;

  return jsonb_build_object(
    'current_streak', coalesce(v_streak,0),
    'longest_streak', coalesce(v_longest,0),
    'quests_completed', coalesce(v_quests_done,0),
    'quests_total', coalesce(v_quests_total,0),
    'achievements', coalesce(v_achievements,0),
    'referrals', coalesce(v_referrals,0),
    'qualified_referrals', coalesce(v_qualified,0),
    'unread_notifications', coalesce(v_unread,0)
  );
end;
$$;

revoke all on function public.sq_get_my_growth_summary() from public;
grant execute on function public.sq_get_my_growth_summary() to authenticated;

-- -----------------------------------------------------------------------------
-- 20. Admin system-status writer
-- -----------------------------------------------------------------------------
create or replace function public.sq_admin_set_system_status(
  p_component text,
  p_status text,
  p_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_component text := lower(btrim(coalesce(p_component,'')));
  v_status text := lower(btrim(coalesce(p_status,'')));
  v_row public.sq_system_status%rowtype;
begin
  if not public.sq_is_admin() then raise exception 'Admin access required.'; end if;
  if v_component = '' then raise exception 'Component is required.'; end if;
  if v_status not in ('operational','degraded','maintenance','incident') then
    raise exception 'Invalid system status.';
  end if;

  update public.sq_system_status
  set status = v_status,
      message = coalesce(nullif(btrim(p_message),''), message),
      updated_by = auth.uid(),
      updated_at = now()
  where component = v_component
  returning * into v_row;

  if not found then raise exception 'Unknown system component.'; end if;

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values(
    auth.uid(),
    'system_status_update',
    'system_status',
    v_component,
    jsonb_build_object('status', v_status, 'message', v_row.message)
  );

  return jsonb_build_object(
    'component', v_row.component,
    'display_name', v_row.display_name,
    'status', v_row.status,
    'message', v_row.message,
    'updated_at', v_row.updated_at
  );
end;
$$;

revoke all on function public.sq_admin_set_system_status(text,text,text) from public, anon;
grant execute on function public.sq_admin_set_system_status(text,text,text) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 21. Admin KPI dashboard
-- -----------------------------------------------------------------------------
create or replace function public.sq_admin_kpis()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_users bigint;
  v_active_rewards bigint;
  v_open_rewards bigint;
  v_completed_rewards bigint;
  v_open_support bigint;
  v_coin_liability bigint;
  v_earned_24h bigint;
  v_new_users_24h bigint;
begin
  if not public.sq_is_admin() then raise exception 'Admin access required.'; end if;

  select count(*) into v_users from public.profiles;
  select count(*) into v_active_rewards from public.reward_items where active = true;
  select count(*) into v_open_rewards from public.redemption_requests where status in ('pending','reviewing','trade_sent');
  select count(*) into v_completed_rewards from public.redemption_requests where status = 'completed';
  select count(*) into v_open_support from public.support_requests where coalesce(status,'new') in ('new','open');
  select coalesce(sum(greatest(coalesce(points_balance,0),0)),0) into v_coin_liability from public.profiles;
  select coalesce(sum(amount),0) into v_earned_24h from public.coin_adjustments where amount > 0 and created_at >= now() - interval '24 hours';
  select count(*) into v_new_users_24h from auth.users where created_at >= now() - interval '24 hours';

  return jsonb_build_object(
    'users', v_users,
    'new_users_24h', v_new_users_24h,
    'active_rewards', v_active_rewards,
    'open_rewards', v_open_rewards,
    'completed_rewards', v_completed_rewards,
    'open_support', v_open_support,
    'coin_liability', v_coin_liability,
    'positive_coin_credits_24h', v_earned_24h
  );
end;
$$;

revoke all on function public.sq_admin_kpis() from public;
grant execute on function public.sq_admin_kpis() to authenticated;

-- -----------------------------------------------------------------------------
-- 22. Trigger helpers
-- -----------------------------------------------------------------------------
create or replace function public.sq_notify_coin_adjustment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.amount > 0 then
    insert into public.sq_notifications(user_id, notification_type, title, body, href, metadata)
    values(
      new.user_id,
      'coins',
      '+' || new.amount || ' coins',
      coalesce(nullif(new.reason,''), 'Coins were added to your wallet.'),
      '/dashboard',
      jsonb_build_object('amount', new.amount)
    );
  end if;

  perform public.sq_refresh_progress_for(new.user_id);
  return new;
end;
$$;

create or replace function public.sq_notify_redemption_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_body text;
begin
  if tg_op = 'INSERT' then
    v_title := 'Reward request received';
    v_body := coalesce(new.reward_name, 'Your reward') || ' is waiting for review.';
  elsif new.status is distinct from old.status then
    v_title := case new.status
      when 'reviewing' then 'Reward under review'
      when 'trade_sent' then 'Steam trade sent'
      when 'completed' then 'Reward completed'
      when 'rejected' then 'Reward request rejected'
      when 'refunded' then 'Reward refunded'
      when 'cancelled' then 'Reward request cancelled'
      else 'Reward status updated'
    end;
    v_body := coalesce(new.reward_name, 'Your reward') || ' is now ' || replace(coalesce(new.status,'updated'),'_',' ') || '.';
  else
    return new;
  end if;

  insert into public.sq_notifications(user_id, notification_type, title, body, href, metadata)
  values(new.user_id, 'reward', v_title, v_body, '/dashboard', jsonb_build_object('request_id',new.id,'status',new.status));

  perform public.sq_refresh_progress_for(new.user_id);
  return new;
end;
$$;

create or replace function public.sq_notify_restock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_available integer;
  v_new_available integer;
begin
  v_old_available := coalesce(old.quantity_total,0) - coalesce(old.quantity_reserved,0);
  v_new_available := coalesce(new.quantity_total,0) - coalesce(new.quantity_reserved,0);

  if v_old_available <= 0 and v_new_available > 0 and coalesce(new.active,false) then
    insert into public.sq_notifications(user_id, notification_type, title, body, href, metadata)
    select s.user_id,
           'stock',
           'Goal reward is back',
           coalesce(new.name,'A reward') || ' is back in stock.',
           '/rewards?reward=' || new.id,
           jsonb_build_object('reward_id',new.id)
    from public.sq_reward_stock_subscriptions s
    where s.reward_id = new.id;

    delete from public.sq_reward_stock_subscriptions where reward_id = new.id;
  end if;
  return new;
end;
$$;

create or replace function public.sq_refresh_after_favorite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.sq_refresh_progress_for(coalesce(new.user_id, old.user_id));
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.sq_refresh_after_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.steam_trade_url is distinct from old.steam_trade_url then
    perform public.sq_refresh_progress_for(new.id);
  end if;
  return new;
end;
$$;

-- Audit only non-sensitive operational fields.
create or replace function public.sq_audit_reward_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.sq_is_admin() then
    insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
    values(
      auth.uid(),
      lower(tg_op),
      'reward_item',
      coalesce(new.id, old.id)::text,
      jsonb_build_object(
        'name', coalesce(new.name, old.name),
        'active_before', case when tg_op = 'INSERT' then null else old.active end,
        'active_after', case when tg_op = 'DELETE' then null else new.active end,
        'total_before', case when tg_op = 'INSERT' then null else old.quantity_total end,
        'total_after', case when tg_op = 'DELETE' then null else new.quantity_total end,
        'reserved_before', case when tg_op = 'INSERT' then null else old.quantity_reserved end,
        'reserved_after', case when tg_op = 'DELETE' then null else new.quantity_reserved end
      )
    );
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- Triggers: replace only names owned by this migration.
drop trigger if exists sq_coin_adjustment_after_insert on public.coin_adjustments;
create trigger sq_coin_adjustment_after_insert
after insert on public.coin_adjustments
for each row execute function public.sq_notify_coin_adjustment();

drop trigger if exists sq_redemption_after_change on public.redemption_requests;
create trigger sq_redemption_after_change
after insert or update of status on public.redemption_requests
for each row execute function public.sq_notify_redemption_change();

drop trigger if exists sq_reward_restock_after_update on public.reward_items;
create trigger sq_reward_restock_after_update
after update of quantity_total, quantity_reserved, active on public.reward_items
for each row execute function public.sq_notify_restock();

drop trigger if exists sq_favorite_after_change on public.favorite_rewards;
create trigger sq_favorite_after_change
after insert or delete on public.favorite_rewards
for each row execute function public.sq_refresh_after_favorite();

drop trigger if exists sq_profile_trade_after_update on public.profiles;
create trigger sq_profile_trade_after_update
after update of steam_trade_url on public.profiles
for each row execute function public.sq_refresh_after_profile();

drop trigger if exists sq_reward_item_audit on public.reward_items;
create trigger sq_reward_item_audit
after insert or update or delete on public.reward_items
for each row execute function public.sq_audit_reward_item();

-- -----------------------------------------------------------------------------
-- 23. Helpful grants for reads already protected by RLS
-- -----------------------------------------------------------------------------
grant select on public.sq_quests, public.sq_achievements, public.sq_system_status to anon, authenticated;
grant select on public.sq_user_streaks, public.sq_daily_activity, public.sq_user_quest_progress,
  public.sq_user_achievements, public.sq_notifications, public.sq_reward_stock_subscriptions,
  public.sq_promo_redemptions, public.sq_referral_codes, public.sq_referrals,
  public.sq_acquisition, public.sq_product_events to authenticated;
grant update(read_at) on public.sq_notifications to authenticated;
grant select, insert, delete on public.sq_reward_stock_subscriptions to authenticated;

-- Admin tables still remain RLS protected.
grant select, insert, update, delete on public.sq_promo_codes, public.sq_system_status to authenticated;
grant select on public.sq_admin_audit_log to authenticated;


-- Initial backfill for existing users. Safe; only derives milestones.
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public.sq_refresh_progress_for(r.id);
  end loop;
end $$;

-- Trigger helpers are internal-only.
revoke all on function public.sq_notify_coin_adjustment() from public, anon, authenticated;
revoke all on function public.sq_notify_redemption_change() from public, anon, authenticated;
revoke all on function public.sq_notify_restock() from public, anon, authenticated;
revoke all on function public.sq_refresh_after_favorite() from public, anon, authenticated;
revoke all on function public.sq_refresh_after_profile() from public, anon, authenticated;
revoke all on function public.sq_audit_reward_item() from public, anon, authenticated;

commit;

-- Refresh PostgREST so newly created tables/RPCs are available immediately.
notify pgrst, 'reload schema';
