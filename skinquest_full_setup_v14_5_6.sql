-- SkinQuest full Supabase setup v14.5.6
-- Includes the dedicated admin operations workspace, traceable case numbers, handler attribution, and hardened admin workflows.
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
  contact_email text,
  contact_email_verified_at timestamptz,
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
alter table public.profiles add column if not exists contact_email text;
alter table public.profiles add column if not exists contact_email_verified_at timestamptz;
alter table public.profiles add column if not exists account_status text not null default 'active';
alter table public.profiles add column if not exists notification_reward_updates boolean not null default true;
alter table public.profiles add column if not exists notification_offer_issues boolean not null default true;
alter table public.profiles add column if not exists notification_product_updates boolean not null default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

create table if not exists public.contact_email_verifications (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  code_hash text not null,
  expires_at timestamptz not null,
  sent_at timestamptz not null default now(),
  attempts integer not null default 0
);

create unique index if not exists profiles_contact_email_unique_idx
on public.profiles (lower(contact_email))
where contact_email is not null and contact_email_verified_at is not null;

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
  order_number text generated always as (
    'SQ-R-' || lpad(id::text, greatest(6, length(id::text)), '0')
  ) stored,
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
  completed_by uuid references auth.users(id) on delete set null,
  last_handled_by uuid references auth.users(id) on delete set null,
  last_handled_at timestamptz,
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
  ticket_number text generated always as (
    'SQ-S-' || lpad(id::text, greatest(6, length(id::text)), '0')
  ) stored,
  user_id uuid references auth.users(id) on delete set null,
  topic text not null,
  message text not null,
  page_url text,
  user_agent text,
  account_email text,
  browser_language text,
  status text not null default 'new',
  admin_note text,
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  last_handled_by uuid references auth.users(id) on delete set null,
  last_handled_at timestamptz,
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

create table if not exists public.password_reset_rate_limits (
  key_hash text primary key,
  last_sent_at timestamptz not null default now()
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
  v_partner text;
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  perform public.ensure_skinquest_profile();
  select * into v_profile from public.profiles where id = v_user_id;

  if v_trade_url is not null and (
    v_trade_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?' or
    v_trade_url !~ '(^|[?&])partner=[0-9]+(&|$)' or
    v_trade_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)'
  ) then
    raise exception 'Invalid Steam trade URL.';
  end if;

  if v_trade_url is not null and v_profile.steam_id ~ '^[0-9]+$' then
    v_partner := substring(v_trade_url from '[?&]partner=([0-9]+)');
    if v_partner is null or v_partner::numeric <> (v_profile.steam_id::numeric - 76561197960265728::numeric) then
      raise exception 'Steam trade URL belongs to a different connected Steam account.';
    end if;
  end if;

  update public.profiles
  set steam_trade_url = v_trade_url, updated_at = now()
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
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_reward public.reward_items%rowtype;
  v_cost integer;
  v_available integer;
  v_request_id bigint;
  v_user_redemptions integer;
  v_auth_email text;
  v_partner text;
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

  select lower(coalesce(email, '')) into v_auth_email from auth.users where id = v_user_id;
  if (v_auth_email = '' or v_auth_email like '%@steam.skinquestcs.com') and
     (nullif(trim(coalesce(v_profile.contact_email, '')), '') is null or v_profile.contact_email_verified_at is null) then
    raise exception 'Verified contact email required.';
  end if;

  if nullif(trim(coalesce(v_profile.steam_trade_url, '')), '') is null then
    raise exception 'Steam trade URL is required.';
  end if;

  if v_profile.steam_trade_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?' or
     v_profile.steam_trade_url !~ '(^|[?&])partner=[0-9]+(&|$)' or
     v_profile.steam_trade_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)' then
    raise exception 'Steam trade URL is invalid.';
  end if;

  if v_profile.steam_id ~ '^[0-9]+$' then
    v_partner := substring(v_profile.steam_trade_url from '[?&]partner=([0-9]+)');
    if v_partner is null or v_partner::numeric <> (v_profile.steam_id::numeric - 76561197960265728::numeric) then
      raise exception 'Steam trade URL belongs to a different connected Steam account.';
    end if;
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
alter table public.contact_email_verifications enable row level security;
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
  coalesce(
    case when p.contact_email_verified_at is not null then p.contact_email else null end,
    case when lower(coalesce(u.email, '')) not like '%@steam.skinquestcs.com' then u.email else null end,
    case when p.username like '%@%' then p.username else null end
  ) as email,
  p.username,
  p.steam_id,
  p.steam_name,
  coalesce(p.notification_reward_updates, true) as reward_updates,
  coalesce(p.notification_offer_issues, true) as offer_issues,
  coalesce(p.notification_product_updates, false) as product_updates,
  p.account_status,
  p.created_at,
  p.updated_at,
  coalesce(p.contact_email_verified_at, u.email_confirmed_at) as email_confirmed_at,
  p.contact_email_verified_at,
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
revoke all on public.contact_email_verifications from anon, authenticated;
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

-- Forgot-password requests are routed through password-reset-request. The browser
-- cannot access the limiter table directly.
alter table public.password_reset_rate_limits enable row level security;
revoke all on public.password_reset_rate_limits from public, anon, authenticated;

create or replace function public.claim_password_reset_rate_limit(p_key_hash text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_last timestamptz;
  v_retry integer;
begin
  if p_key_hash is null or length(trim(p_key_hash)) < 16 then
    raise exception 'Invalid rate-limit key.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_key_hash, 0));

  select last_sent_at
    into v_last
    from public.password_reset_rate_limits
   where key_hash = p_key_hash;

  if v_last is not null and v_last > v_now - interval '60 seconds' then
    v_retry := greatest(
      1,
      ceil(extract(epoch from ((v_last + interval '60 seconds') - v_now)))::integer
    );
    return v_retry;
  end if;

  insert into public.password_reset_rate_limits(key_hash, last_sent_at)
  values (p_key_hash, v_now)
  on conflict (key_hash) do update
    set last_sent_at = excluded.last_sent_at;

  return 0;
end;
$$;

revoke all on function public.claim_password_reset_rate_limit(text) from public, anon, authenticated;
grant execute on function public.claim_password_reset_rate_limit(text) to service_role;

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
-- SkinQuest v14 product layer (included in full fresh-project setup)
-- Existing v14.0.2 projects already contain this database layer.
-- v14.3.0 retains verified contact email storage, stronger trade-link checks, private notification access, and password-reset throttling.
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
    raise exception 'SkinQuest setup requires the existing core schema. Use skinquest_full_setup_v14_4_0.sql only for a NEW empty Supabase project.';
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
using (auth.uid() = user_id);

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

-- =============================================================================
-- v14.3.0 admin operations and case-management layer
-- =============================================================================
begin;

-- -----------------------------------------------------------------------------
-- 1. Stable public-facing case numbers and handler accountability
-- -----------------------------------------------------------------------------

alter table public.redemption_requests
  add column if not exists order_number text generated always as (
    'SQ-R-' || lpad(id::text, greatest(6, length(id::text)), '0')
  ) stored;

alter table public.redemption_requests
  add column if not exists completed_by uuid references auth.users(id) on delete set null;

alter table public.redemption_requests
  add column if not exists last_handled_by uuid references auth.users(id) on delete set null;

alter table public.redemption_requests
  add column if not exists last_handled_at timestamptz;

alter table public.support_requests
  add column if not exists ticket_number text generated always as (
    'SQ-S-' || lpad(id::text, greatest(6, length(id::text)), '0')
  ) stored;

alter table public.support_requests
  add column if not exists resolved_at timestamptz;

alter table public.support_requests
  add column if not exists resolved_by uuid references auth.users(id) on delete set null;

alter table public.support_requests
  add column if not exists last_handled_by uuid references auth.users(id) on delete set null;

alter table public.support_requests
  add column if not exists last_handled_at timestamptz;

update public.support_requests
set resolved_at = coalesce(updated_at, created_at)
where status = 'resolved' and resolved_at is null;

create unique index if not exists redemption_requests_order_number_idx
  on public.redemption_requests (order_number);

create unique index if not exists support_requests_ticket_number_idx
  on public.support_requests (ticket_number);

create index if not exists redemption_requests_admin_queue_idx
  on public.redemption_requests (status, created_at desc);

create index if not exists support_requests_admin_queue_idx
  on public.support_requests (status, created_at desc);

-- -----------------------------------------------------------------------------
-- 2. Owner-only team access with last-owner protection and audit history
-- -----------------------------------------------------------------------------

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
  v_actor_id uuid := auth.uid();
  v_user_id uuid;
  v_role text := lower(trim(coalesce(p_role, '')));
  v_previous_role text;
  v_next_role text;
  v_owner_count integer;
begin
  if not public.is_owner() then
    raise exception 'Owner access required.';
  end if;

  if p_user_identifier is null or length(trim(p_user_identifier)) = 0 or length(p_user_identifier) > 320 then
    raise exception 'Enter a valid user email or ID.';
  end if;

  begin
    v_user_id := trim(p_user_identifier)::uuid;
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

  if v_role not in ('admin', 'owner', 'remove', 'none', 'user', '') then
    raise exception 'Invalid role.';
  end if;

  lock table public.admin_users in share row exclusive mode;

  select role into v_previous_role
  from public.admin_users
  where user_id = v_user_id;

  v_next_role := case when v_role in ('remove', 'none', 'user', '') then null else v_role end;

  if v_previous_role = 'owner' and v_next_role is distinct from 'owner' then
    select count(*) into v_owner_count
    from public.admin_users
    where role = 'owner';

    if v_owner_count <= 1 then
      raise exception 'The last owner cannot be removed or demoted.';
    end if;
  end if;

  if v_next_role is null then
    delete from public.admin_users where user_id = v_user_id;
  else
    insert into public.admin_users (user_id, role)
    values (v_user_id, v_next_role)
    on conflict (user_id) do update set role = excluded.role;
  end if;

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values (
    v_actor_id,
    'admin_role_update',
    'admin_user',
    v_user_id::text,
    jsonb_build_object('previous_role', v_previous_role, 'role', v_next_role)
  );

  return jsonb_build_object('ok', true, 'user_id', v_user_id, 'role', v_next_role);
end;
$$;

revoke all on function public.owner_set_admin_role(text, text) from public, anon, authenticated;
grant execute on function public.owner_set_admin_role(text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Owner-only coin correction with exact accounting and audit history
-- -----------------------------------------------------------------------------

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
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_previous_balance integer;
  v_new_balance bigint;
begin
  if not public.is_owner() then
    raise exception 'Owner access required.';
  end if;

  if p_user_identifier is null or length(trim(p_user_identifier)) = 0 or length(p_user_identifier) > 320 then
    raise exception 'Enter a valid user email or ID.';
  end if;

  if p_amount is null or p_amount = 0 or abs(p_amount::bigint) > 1000000 then
    raise exception 'Amount must be between -1,000,000 and 1,000,000 and cannot be zero.';
  end if;

  if v_reason is null or length(v_reason) < 4 or length(v_reason) > 240 then
    raise exception 'A reason between 4 and 240 characters is required.';
  end if;

  begin
    v_user_id := trim(p_user_identifier)::uuid;
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

  select coalesce(points_balance, 0) into v_previous_balance
  from public.profiles
  where id = v_user_id
  for update;

  v_new_balance := v_previous_balance::bigint + p_amount::bigint;

  if v_new_balance < 0 then
    raise exception 'Adjustment would make the balance negative.';
  end if;

  if v_new_balance > 2147483647 then
    raise exception 'Resulting balance is too large.';
  end if;

  update public.profiles
  set points_balance = v_new_balance::integer,
      updated_at = now()
  where id = v_user_id;

  insert into public.coin_adjustments (user_id, amount, reason, source_type, created_by)
  values (v_user_id, p_amount, v_reason, 'admin_adjustment', v_admin_id);

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values (
    v_admin_id,
    'coin_adjustment',
    'profile',
    v_user_id::text,
    jsonb_build_object(
      'amount', p_amount,
      'reason', v_reason,
      'previous_balance', v_previous_balance,
      'balance', v_new_balance
    )
  );

  return jsonb_build_object(
    'ok', true,
    'user_id', v_user_id,
    'amount', p_amount,
    'previous_balance', v_previous_balance,
    'balance', v_new_balance
  );
end;
$$;

revoke all on function public.admin_adjust_user_coins(text, integer, text) from public, anon, authenticated;
grant execute on function public.admin_adjust_user_coins(text, integer, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Secure redemption workflow with terminal-state protection and audit trail
-- -----------------------------------------------------------------------------

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
  v_status text := lower(trim(coalesce(p_status, '')));
  v_note text := nullif(trim(coalesce(p_admin_note, '')), '');
  v_trade_offer_url text := nullif(trim(coalesce(p_trade_offer_url, '')), '');
  v_cost integer;
  v_release_stock boolean := false;
  v_refund boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  if p_request_id is null or p_request_id < 1 then
    raise exception 'Invalid request.';
  end if;

  if v_status not in ('pending', 'reviewing', 'trade_sent', 'completed', 'rejected', 'refunded', 'cancelled') then
    raise exception 'Invalid status.';
  end if;

  if v_note is not null and length(v_note) > 2000 then
    raise exception 'Admin note is too long.';
  end if;

  if v_trade_offer_url is not null and (
    length(v_trade_offer_url) > 500 or
    v_trade_offer_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/'
  ) then
    raise exception 'Enter a valid HTTPS Steam trade-offer URL.';
  end if;

  select * into v_request
  from public.redemption_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Request not found.';
  end if;

  v_old_status := v_request.status;

  if v_old_status in ('completed', 'rejected', 'refunded', 'cancelled') and v_status <> v_old_status then
    raise exception 'Completed, rejected, refunded, and cancelled orders cannot be reopened. Create a documented correction instead.';
  end if;

  if v_status = 'trade_sent' and coalesce(v_trade_offer_url, v_request.trade_offer_url) is null then
    raise exception 'A Steam trade-offer URL is required before marking the order as trade sent.';
  end if;

  v_cost := coalesce(nullif(v_request.points_coins, 0), v_request.points_cost, 0);

  if v_status in ('rejected', 'refunded', 'cancelled') and v_request.refunded_at is null then
    v_refund := true;
    v_release_stock := v_old_status <> 'completed';
  elsif v_status = 'completed' and v_request.completed_at is null then
    v_release_stock := true;
  end if;

  if v_refund then
    update public.profiles
    set points_balance = coalesce(points_balance, 0) + v_cost,
        updated_at = now()
    where id = v_request.user_id;

    insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, created_by, metadata)
    values (
      v_request.user_id,
      v_cost,
      'Redeem refund / ' || v_request.reward_name,
      'redemption_refund',
      v_request.id::text,
      v_admin_id,
      jsonb_build_object('old_status', v_old_status, 'new_status', v_status)
    );
  end if;

  if v_release_stock and v_request.reward_id is not null then
    if v_status = 'completed' then
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved, 0) - 1),
          quantity_total = greatest(0, coalesce(quantity_total, 0) - 1),
          updated_at = now()
      where id = v_request.reward_id;
    else
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved, 0) - 1),
          updated_at = now()
      where id = v_request.reward_id;
    end if;
  end if;

  update public.redemption_requests
  set status = v_status,
      admin_note = v_note,
      trade_offer_url = v_trade_offer_url,
      refunded_at = case when v_refund then now() else refunded_at end,
      completed_at = case when v_status = 'completed' then coalesce(completed_at, now()) else completed_at end,
      completed_by = case when v_status = 'completed' then coalesce(completed_by, v_admin_id) else completed_by end,
      last_handled_by = v_admin_id,
      last_handled_at = now(),
      updated_at = now()
  where id = p_request_id;

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values (
    v_admin_id,
    'redemption_status_update',
    'redemption_request',
    p_request_id::text,
    jsonb_build_object(
      'order_number', v_request.order_number,
      'from_status', v_old_status,
      'to_status', v_status,
      'note_changed', v_request.admin_note is distinct from v_note,
      'trade_proof_changed', v_request.trade_offer_url is distinct from v_trade_offer_url,
      'refunded', v_refund
    )
  );

  return jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'order_number', v_request.order_number,
    'status', v_status,
    'refunded', v_refund
  );
end;
$$;

revoke all on function public.admin_update_redemption_status(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_update_redemption_status(bigint, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Support workflow is RPC-only, attributable, and auditable
-- -----------------------------------------------------------------------------

create or replace function public.sq_admin_update_support_status(
  p_request_id bigint,
  p_status text,
  p_admin_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid := auth.uid();
  v_request public.support_requests%rowtype;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_note text := nullif(trim(coalesce(p_admin_note, '')), '');
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  if p_request_id is null or p_request_id < 1 then
    raise exception 'Invalid request.';
  end if;

  if v_status not in ('new', 'open', 'resolved') then
    raise exception 'Invalid status.';
  end if;

  if v_note is not null and length(v_note) > 2000 then
    raise exception 'Admin note is too long.';
  end if;

  select * into v_request
  from public.support_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Support request not found.';
  end if;

  update public.support_requests
  set status = v_status,
      admin_note = v_note,
      resolved_at = case
        when v_status = 'resolved' then coalesce(resolved_at, now())
        else null
      end,
      resolved_by = case
        when v_status = 'resolved' then coalesce(resolved_by, v_admin_id)
        else null
      end,
      last_handled_by = v_admin_id,
      last_handled_at = now(),
      updated_at = now()
  where id = p_request_id;

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values (
    v_admin_id,
    'support_status_update',
    'support_request',
    p_request_id::text,
    jsonb_build_object(
      'ticket_number', v_request.ticket_number,
      'from_status', v_request.status,
      'to_status', v_status,
      'note_changed', v_request.admin_note is distinct from v_note
    )
  );

  return jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'ticket_number', v_request.ticket_number,
    'status', v_status
  );
end;
$$;

revoke update on public.support_requests from anon, authenticated;
revoke insert, update, delete on public.sq_system_status from anon, authenticated;
revoke insert, update, delete on public.sq_promo_codes from anon, authenticated;
revoke all on function public.sq_admin_update_support_status(bigint, text, text) from public, anon, authenticated;
grant execute on function public.sq_admin_update_support_status(bigint, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. Bounded, admin-only historical case search
-- -----------------------------------------------------------------------------

create or replace function public.sq_admin_search_redemptions(
  p_query text default null,
  p_status text default 'open',
  p_limit integer default 75,
  p_offset integer default 0
)
returns setof public.redemption_requests
language plpgsql
security definer
stable
set search_path = public, auth
as $$
declare
  v_query text := left(trim(coalesce(p_query, '')), 120);
  v_status text := lower(trim(coalesce(p_status, 'open')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 75), 200));
  v_offset integer := greatest(0, least(coalesce(p_offset, 0), 100000));
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  if v_status not in ('open', 'all', 'pending', 'reviewing', 'trade_sent', 'completed', 'rejected', 'refunded', 'cancelled') then
    raise exception 'Invalid status filter.';
  end if;

  return query
  select r.*
  from public.redemption_requests r
  left join public.profiles p on p.id = r.user_id
  left join auth.users u on u.id = r.user_id
  where (
    v_status = 'all' or
    (v_status = 'open' and r.status in ('pending', 'reviewing', 'trade_sent')) or
    r.status = v_status
  )
  and (
    v_query = '' or
    r.order_number ilike '%' || v_query || '%' or
    r.id::text = v_query or
    r.user_id::text ilike '%' || v_query || '%' or
    coalesce(r.reward_name, '') ilike '%' || v_query || '%' or
    coalesce(r.admin_note, '') ilike '%' || v_query || '%' or
    coalesce(p.username, '') ilike '%' || v_query || '%' or
    coalesce(p.steam_name, '') ilike '%' || v_query || '%' or
    coalesce(p.contact_email, '') ilike '%' || v_query || '%' or
    coalesce(u.email, '') ilike '%' || v_query || '%'
  )
  order by r.created_at desc, r.id desc
  limit v_limit
  offset v_offset;
end;
$$;

create or replace function public.sq_admin_search_support(
  p_query text default null,
  p_status text default 'open',
  p_limit integer default 75,
  p_offset integer default 0
)
returns setof public.support_requests
language plpgsql
security definer
stable
set search_path = public, auth
as $$
declare
  v_query text := left(trim(coalesce(p_query, '')), 120);
  v_status text := lower(trim(coalesce(p_status, 'open')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 75), 200));
  v_offset integer := greatest(0, least(coalesce(p_offset, 0), 100000));
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  if v_status not in ('open', 'all', 'new', 'resolved') then
    raise exception 'Invalid status filter.';
  end if;

  return query
  select s.*
  from public.support_requests s
  left join public.profiles p on p.id = s.user_id
  left join auth.users u on u.id = s.user_id
  where (
    v_status = 'all' or
    (v_status = 'open' and s.status in ('new', 'open')) or
    s.status = v_status
  )
  and (
    v_query = '' or
    s.ticket_number ilike '%' || v_query || '%' or
    s.id::text = v_query or
    s.user_id::text ilike '%' || v_query || '%' or
    coalesce(s.topic, '') ilike '%' || v_query || '%' or
    coalesce(s.message, '') ilike '%' || v_query || '%' or
    coalesce(s.account_email, '') ilike '%' || v_query || '%' or
    coalesce(s.admin_note, '') ilike '%' || v_query || '%' or
    coalesce(p.username, '') ilike '%' || v_query || '%' or
    coalesce(p.steam_name, '') ilike '%' || v_query || '%' or
    coalesce(p.contact_email, '') ilike '%' || v_query || '%' or
    coalesce(u.email, '') ilike '%' || v_query || '%'
  )
  order by s.created_at desc, s.id desc
  limit v_limit
  offset v_offset;
end;
$$;

create or replace function public.sq_admin_directory()
returns table (
  user_id uuid,
  role text,
  email text,
  username text,
  steam_name text,
  created_at timestamptz
)
language plpgsql
security definer
stable
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  return query
  select
    au.user_id,
    au.role,
    u.email::text,
    p.username,
    p.steam_name,
    au.created_at
  from public.admin_users au
  left join auth.users u on u.id = au.user_id
  left join public.profiles p on p.id = au.user_id
  order by case au.role when 'owner' then 0 else 1 end, au.created_at asc;
end;
$$;

revoke all on function public.sq_admin_directory() from public, anon, authenticated;
revoke all on function public.sq_admin_search_redemptions(text, text, integer, integer) from public, anon, authenticated;
revoke all on function public.sq_admin_search_support(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.sq_admin_search_redemptions(text, text, integer, integer) to authenticated;
grant execute on function public.sq_admin_search_support(text, text, integer, integer) to authenticated;
grant execute on function public.sq_admin_directory() to authenticated;

commit;

notify pgrst, 'reload schema';

-- End of v14.3.0-only upgrade.


-- =============================================================================
-- v14.4.1 order and fulfilment system
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. Reward fulfilment model
-- -----------------------------------------------------------------------------
alter table public.reward_items
  add column if not exists fulfillment_mode text not null default 'stocked';

alter table public.reward_items
  add column if not exists order_eta_days integer not null default 8;

do $$
begin
  alter table public.reward_items
    add constraint reward_items_fulfillment_mode_check
    check (fulfillment_mode in ('stocked', 'orderable'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.reward_items
    add constraint reward_items_order_eta_days_check
    check (order_eta_days between 7 and 30);
exception when duplicate_object then null;
end $$;

-- Snapshot fulfilment details onto each order so later reward edits cannot
-- rewrite the meaning of an already-paid customer order.
alter table public.redemption_requests
  add column if not exists fulfillment_mode text not null default 'stocked';

alter table public.redemption_requests
  add column if not exists estimated_ready_at timestamptz;

alter table public.redemption_requests
  add column if not exists purchased_at timestamptz;

alter table public.redemption_requests
  add column if not exists trade_locked_until timestamptz;

alter table public.redemption_requests
  add column if not exists ready_at timestamptz;

alter table public.redemption_requests
  add column if not exists trade_sent_at timestamptz;

alter table public.redemption_requests
  add column if not exists last_notified_status text;

alter table public.redemption_requests
  add column if not exists status_notified_at timestamptz;

do $$
begin
  alter table public.redemption_requests
    add constraint redemption_requests_fulfillment_mode_check
    check (fulfillment_mode in ('stocked', 'orderable'));
exception when duplicate_object then null;
end $$;

create index if not exists redemption_requests_trade_lock_idx
  on public.redemption_requests (trade_locked_until)
  where status = 'trade_locked';

-- Existing v14.3.0 orders were stock-based orders.
update public.redemption_requests
set fulfillment_mode = 'stocked'
where fulfillment_mode is null or fulfillment_mode not in ('stocked', 'orderable');

-- -----------------------------------------------------------------------------
-- 2. Redeem / order creation
-- -----------------------------------------------------------------------------
create or replace function public.redeem_reward(p_reward_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_reward public.reward_items%rowtype;
  v_cost integer;
  v_available integer;
  v_request_id bigint;
  v_order_number text;
  v_user_redemptions integer;
  v_auth_email text;
  v_partner text;
  v_mode text;
  v_status text;
  v_estimated_ready_at timestamptz;
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

  select lower(coalesce(email, '')) into v_auth_email from auth.users where id = v_user_id;
  if (v_auth_email = '' or v_auth_email like '%@steam.skinquestcs.com') and
     (nullif(trim(coalesce(v_profile.contact_email, '')), '') is null or v_profile.contact_email_verified_at is null) then
    raise exception 'Verified contact email required.';
  end if;

  if nullif(trim(coalesce(v_profile.steam_trade_url, '')), '') is null then
    raise exception 'Steam trade URL is required.';
  end if;

  if v_profile.steam_trade_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?' or
     v_profile.steam_trade_url !~ '(^|[?&])partner=[0-9]+(&|$)' or
     v_profile.steam_trade_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)' then
    raise exception 'Steam trade URL is invalid.';
  end if;

  if v_profile.steam_id ~ '^[0-9]+$' then
    v_partner := substring(v_profile.steam_trade_url from '[?&]partner=([0-9]+)');
    if v_partner is null or v_partner::numeric <> (v_profile.steam_id::numeric - 76561197960265728::numeric) then
      raise exception 'Steam trade URL belongs to a different connected Steam account.';
    end if;
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

  v_mode := case when v_reward.fulfillment_mode = 'orderable' then 'orderable' else 'stocked' end;

  if v_mode = 'stocked' then
    v_available := greatest(0, coalesce(v_reward.quantity_total, 0) - coalesce(v_reward.quantity_reserved, 0));
    if v_available <= 0 then
      raise exception 'Reward is out of stock.';
    end if;
    v_status := 'ready_to_trade';
    v_estimated_ready_at := now() + interval '2 days';
  else
    v_status := 'ordered';
    v_estimated_ready_at := now() + make_interval(days => greatest(7, least(coalesce(v_reward.order_eta_days, 8), 30)));
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
  set points_balance = points_balance - v_cost,
      updated_at = now()
  where id = v_user_id;

  -- Only already-owned/prepared inventory is reserved. Orderable rewards are
  -- purchased after the customer order and must never consume phantom stock.
  if v_mode = 'stocked' then
    update public.reward_items
    set quantity_reserved = coalesce(quantity_reserved, 0) + 1,
        updated_at = now()
    where id = v_reward.id;
  end if;

  insert into public.redemption_requests (
    user_id, reward_id, reward_name, points_coins, points_cost, steam_trade_url,
    status, fulfillment_mode, estimated_ready_at, ready_at
  ) values (
    v_user_id, v_reward.id, v_reward.name, v_cost, v_cost, v_profile.steam_trade_url,
    v_status, v_mode, v_estimated_ready_at,
    case when v_status = 'ready_to_trade' then now() else null end
  ) returning id, order_number into v_request_id, v_order_number;

  insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, metadata)
  values (
    v_user_id,
    -v_cost,
    case when v_mode = 'orderable' then 'Reward order / ' else 'Redeem hold / ' end || v_reward.name,
    case when v_mode = 'orderable' then 'reward_order' else 'redemption_hold' end,
    v_request_id::text,
    jsonb_build_object(
      'reward_id', v_reward.id,
      'reward_name', v_reward.name,
      'fulfillment_mode', v_mode,
      'status', v_status
    )
  );

  return jsonb_build_object(
    'ok', true,
    'request_id', v_request_id,
    'order_number', v_order_number,
    'fulfillment_mode', v_mode,
    'status', v_status,
    'estimated_ready_at', v_estimated_ready_at
  );
end;
$$;

revoke all on function public.redeem_reward(bigint) from public, anon;
grant execute on function public.redeem_reward(bigint) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Admin order lifecycle
-- -----------------------------------------------------------------------------
create or replace function public.sq_admin_update_order(
  p_request_id bigint,
  p_status text,
  p_admin_note text default null,
  p_trade_offer_url text default null,
  p_trade_locked_until timestamptz default null
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
  v_status text := lower(trim(coalesce(p_status, '')));
  v_note text := nullif(trim(coalesce(p_admin_note, '')), '');
  v_trade_offer_url text := nullif(trim(coalesce(p_trade_offer_url, '')), '');
  v_trade_locked_until timestamptz := p_trade_locked_until;
  v_cost integer;
  v_release_stock boolean := false;
  v_refund boolean := false;
  v_final_trade_url text;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  if p_request_id is null or p_request_id < 1 then
    raise exception 'Invalid order.';
  end if;

  if v_status not in (
    'pending', 'reviewing', 'ordered', 'trade_locked', 'ready_to_trade',
    'trade_sent', 'completed', 'rejected', 'refunded', 'cancelled'
  ) then
    raise exception 'Invalid order status.';
  end if;

  if v_note is not null and length(v_note) > 2000 then
    raise exception 'Admin note is too long.';
  end if;

  if v_trade_offer_url is not null and (
    length(v_trade_offer_url) > 500 or
    v_trade_offer_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/'
  ) then
    raise exception 'Enter a valid HTTPS Steam trade-offer URL.';
  end if;

  select * into v_request
  from public.redemption_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Order not found.';
  end if;

  v_old_status := v_request.status;
  v_final_trade_url := coalesce(v_trade_offer_url, v_request.trade_offer_url);

  if v_old_status in ('completed', 'rejected', 'refunded', 'cancelled') and v_status <> v_old_status then
    raise exception 'Completed, rejected, refunded, and cancelled orders cannot be reopened.';
  end if;

  if v_status = 'trade_locked' then
    if v_trade_locked_until is null then
      v_trade_locked_until := v_request.trade_locked_until;
    end if;
    if v_trade_locked_until is null then
      raise exception 'Enter the Steam trade-lock end time.';
    end if;
    if v_trade_locked_until <= now() then
      raise exception 'Trade-lock end time must be in the future. Use Ready to trade if it is already unlocked.';
    end if;
  end if;

  if v_status = 'trade_sent' and v_final_trade_url is null then
    raise exception 'A Steam trade-offer URL is required before marking the order as Trade sent.';
  end if;

  if v_status = 'completed' and coalesce(v_final_trade_url, '') = '' then
    raise exception 'A Steam trade-offer URL is required before completing the order.';
  end if;

  v_cost := coalesce(nullif(v_request.points_coins, 0), v_request.points_cost, 0);

  if v_status in ('rejected', 'refunded', 'cancelled') and v_request.refunded_at is null then
    v_refund := true;
    v_release_stock := v_request.fulfillment_mode = 'stocked' and v_old_status <> 'completed';
  elsif v_status = 'completed' and v_request.completed_at is null then
    v_release_stock := v_request.fulfillment_mode = 'stocked';
  end if;

  if v_refund then
    update public.profiles
    set points_balance = coalesce(points_balance, 0) + v_cost,
        updated_at = now()
    where id = v_request.user_id;

    insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, created_by, metadata)
    values (
      v_request.user_id,
      v_cost,
      'Reward order refund / ' || v_request.reward_name,
      'redemption_refund',
      v_request.id::text,
      v_admin_id,
      jsonb_build_object('old_status', v_old_status, 'new_status', v_status, 'fulfillment_mode', v_request.fulfillment_mode)
    );
  end if;

  if v_release_stock and v_request.reward_id is not null then
    if v_status = 'completed' then
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved, 0) - 1),
          quantity_total = greatest(0, coalesce(quantity_total, 0) - 1),
          updated_at = now()
      where id = v_request.reward_id;
    else
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved, 0) - 1),
          updated_at = now()
      where id = v_request.reward_id;
    end if;
  end if;

  update public.redemption_requests
  set status = v_status,
      admin_note = v_note,
      trade_offer_url = v_final_trade_url,
      purchased_at = case when v_status = 'trade_locked' then coalesce(purchased_at, now()) else purchased_at end,
      trade_locked_until = case
        when v_status = 'trade_locked' then v_trade_locked_until
        else trade_locked_until
      end,
      estimated_ready_at = case
        when v_status = 'trade_locked' then v_trade_locked_until
        else estimated_ready_at
      end,
      ready_at = case when v_status = 'ready_to_trade' then coalesce(ready_at, now()) else ready_at end,
      trade_sent_at = case when v_status = 'trade_sent' then coalesce(trade_sent_at, now()) else trade_sent_at end,
      refunded_at = case when v_refund then now() else refunded_at end,
      completed_at = case when v_status = 'completed' then coalesce(completed_at, now()) else completed_at end,
      completed_by = case when v_status = 'completed' then coalesce(completed_by, v_admin_id) else completed_by end,
      last_handled_by = v_admin_id,
      last_handled_at = now(),
      updated_at = now()
  where id = p_request_id;

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values (
    v_admin_id,
    'redemption_status_update',
    'redemption_request',
    p_request_id::text,
    jsonb_build_object(
      'order_number', v_request.order_number,
      'fulfillment_mode', v_request.fulfillment_mode,
      'from_status', v_old_status,
      'to_status', v_status,
      'trade_locked_until', v_trade_locked_until,
      'note_changed', v_request.admin_note is distinct from v_note,
      'trade_proof_changed', v_request.trade_offer_url is distinct from v_final_trade_url,
      'refunded', v_refund
    )
  );

  return jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'order_number', v_request.order_number,
    'status', v_status,
    'refunded', v_refund,
    'trade_locked_until', v_trade_locked_until
  );
end;
$$;

revoke all on function public.sq_admin_update_order(bigint, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.sq_admin_update_order(bigint, text, text, text, timestamptz) to authenticated;

-- Keep the v14.3 RPC safe for old cached clients. It delegates to the new logic
-- and cannot bypass the v14.4 stock/refund rules.
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
begin
  return public.sq_admin_update_order(
    p_request_id,
    p_status,
    p_admin_note,
    p_trade_offer_url,
    null
  );
end;
$$;

revoke all on function public.admin_update_redemption_status(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_update_redemption_status(bigint, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Expired trade locks -> Ready to trade
-- -----------------------------------------------------------------------------
create or replace function public.sq_admin_refresh_trade_locks()
returns table(request_id bigint, order_number text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row record;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  for v_row in
    select id, redemption_requests.order_number
    from public.redemption_requests
    where status = 'trade_locked'
      and trade_locked_until is not null
      and trade_locked_until <= now()
    for update skip locked
  loop
    update public.redemption_requests
    set status = 'ready_to_trade',
        ready_at = coalesce(ready_at, now()),
        updated_at = now()
    where id = v_row.id;

    insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
    values (
      auth.uid(),
      'trade_lock_expired',
      'redemption_request',
      v_row.id::text,
      jsonb_build_object('order_number', v_row.order_number, 'to_status', 'ready_to_trade')
    );

    request_id := v_row.id;
    order_number := v_row.order_number;
    return next;
  end loop;
end;
$$;

revoke all on function public.sq_admin_refresh_trade_locks() from public, anon, authenticated;
grant execute on function public.sq_admin_refresh_trade_locks() to authenticated;

-- -----------------------------------------------------------------------------
-- 5. In-app order notifications
-- -----------------------------------------------------------------------------
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
    if new.status = 'ordered' then
      v_title := 'Reward order placed';
      v_body := coalesce(new.reward_name, 'Your reward') || ' is available to order. SkinQuest will purchase it and then show the Steam trade-lock countdown here.';
    elsif new.status = 'ready_to_trade' then
      v_title := 'Reward ready for fulfilment';
      v_body := coalesce(new.reward_name, 'Your reward') || ' is already in stock and ready for SkinQuest to send.';
    else
      v_title := 'Reward order received';
      v_body := coalesce(new.reward_name, 'Your reward') || ' was added to your orders.';
    end if;
  elsif new.status is distinct from old.status then
    v_title := case new.status
      when 'reviewing' then 'Reward under review'
      when 'ordered' then 'Reward order placed'
      when 'trade_locked' then 'Reward purchased — trade locked'
      when 'ready_to_trade' then 'Reward ready to trade'
      when 'trade_sent' then 'Steam trade sent'
      when 'completed' then 'Reward completed'
      when 'rejected' then 'Reward order rejected'
      when 'refunded' then 'Reward refunded'
      when 'cancelled' then 'Reward order cancelled'
      else 'Reward status updated'
    end;

    v_body := case new.status
      when 'trade_locked' then coalesce(new.reward_name, 'Your reward') || ' has been purchased. The Steam trade lock is now counting down.'
      when 'ready_to_trade' then coalesce(new.reward_name, 'Your reward') || ' is unlocked and ready for SkinQuest to send.'
      when 'trade_sent' then coalesce(new.reward_name, 'Your reward') || ' has been sent as a Steam trade offer.'
      else coalesce(new.reward_name, 'Your reward') || ' is now ' || replace(coalesce(new.status,'updated'),'_',' ') || '.'
    end;
  else
    return new;
  end if;

  insert into public.sq_notifications(user_id, notification_type, title, body, href, metadata)
  values(
    new.user_id,
    'reward',
    v_title,
    v_body,
    '/dashboard?request=' || new.id,
    jsonb_build_object(
      'request_id', new.id,
      'status', new.status,
      'fulfillment_mode', new.fulfillment_mode,
      'trade_locked_until', new.trade_locked_until
    )
  );

  perform public.sq_refresh_progress_for(new.user_id);
  return new;
end;
$$;


-- Reward audit/restock helpers understand fulfilment mode.
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
        'fulfillment_before', case when tg_op = 'INSERT' then null else old.fulfillment_mode end,
        'fulfillment_after', case when tg_op = 'DELETE' then null else new.fulfillment_mode end,
        'order_eta_before', case when tg_op = 'INSERT' then null else old.order_eta_days end,
        'order_eta_after', case when tg_op = 'DELETE' then null else new.order_eta_days end,
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
  -- Orderable rewards are always orderable; physical-stock alerts only apply to prepared inventory.
  if new.fulfillment_mode = 'orderable' then
    return new;
  end if;

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



-- Recreate the stock notification trigger so switching a listing from
-- orderable -> stocked is evaluated the same way as a physical restock.
drop trigger if exists sq_reward_restock_after_update on public.reward_items;
create trigger sq_reward_restock_after_update
after update of quantity_total, quantity_reserved, active, fulfillment_mode on public.reward_items
for each row execute function public.sq_notify_restock();

-- -----------------------------------------------------------------------------
-- 6. Admin/public queries understand the new open states
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
    'open_rewards', (
      select count(*) from public.redemption_requests
      where status in ('pending','reviewing','ordered','trade_locked','ready_to_trade','trade_sent')
    )
  );
$$;

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
  select count(*) into v_open_rewards from public.redemption_requests where status in ('pending','reviewing','ordered','trade_locked','ready_to_trade','trade_sent');
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

create or replace function public.sq_admin_search_redemptions(
  p_query text default null,
  p_status text default 'open',
  p_limit integer default 75,
  p_offset integer default 0
)
returns setof public.redemption_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_query text := lower(trim(coalesce(p_query, '')));
  v_status text := lower(trim(coalesce(p_status, 'open')));
  v_limit integer := least(greatest(coalesce(p_limit, 75), 1), 250);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  if v_status not in (
    'open', 'all', 'pending', 'reviewing', 'ordered', 'trade_locked',
    'ready_to_trade', 'trade_sent', 'completed', 'rejected', 'refunded', 'cancelled'
  ) then
    raise exception 'Invalid order status filter.';
  end if;

  return query
  select r.*
  from public.redemption_requests r
  where (
    v_status = 'all' or
    (v_status = 'open' and r.status in ('pending','reviewing','ordered','trade_locked','ready_to_trade','trade_sent')) or
    r.status = v_status
  )
  and (
    v_query = '' or
    r.order_number ilike '%' || v_query || '%' or
    r.id::text ilike '%' || v_query || '%' or
    r.user_id::text ilike '%' || v_query || '%' or
    coalesce(r.reward_name, '') ilike '%' || v_query || '%' or
    coalesce(r.admin_note, '') ilike '%' || v_query || '%'
  )
  order by r.created_at desc, r.id desc
  limit v_limit offset v_offset;
end;
$$;

revoke all on function public.sq_public_stats() from public;
grant execute on function public.sq_public_stats() to anon, authenticated;
revoke all on function public.sq_admin_kpis() from public, anon;
grant execute on function public.sq_admin_kpis() to authenticated;
revoke all on function public.sq_admin_search_redemptions(text, text, integer, integer) from public, anon;
grant execute on function public.sq_admin_search_redemptions(text, text, integer, integer) to authenticated;

commit;
-- End of v14.4.1-only upgrade.

-- =============================================================================
-- v14.4.1 hardening: safe order transitions + inventory invariants
-- =============================================================================
begin;

alter table public.redemption_requests
  add column if not exists last_user_notified_status text;
alter table public.redemption_requests
  add column if not exists user_status_notified_at timestamptz;
alter table public.redemption_requests
  add column if not exists ready_admin_notified_at timestamptz;

-- Backfill the new user-status marker only where the older marker was known.
update public.redemption_requests
set last_user_notified_status = coalesce(last_user_notified_status, last_notified_status),
    user_status_notified_at = coalesce(user_status_notified_at, status_notified_at)
where last_notified_status is not null;

-- Keep inventory sane even if a future client bypasses the browser checks.
create or replace function public.sq_validate_reward_inventory()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(new.quantity_total, 0) < 0 then
    raise exception 'Total stock cannot be negative.';
  end if;
  if coalesce(new.quantity_reserved, 0) < 0 then
    raise exception 'Reserved stock cannot be negative.';
  end if;
  if coalesce(new.quantity_reserved, 0) > coalesce(new.quantity_total, 0) then
    raise exception 'Reserved stock cannot be higher than total stock.';
  end if;

  if tg_op = 'UPDATE'
     and coalesce(old.fulfillment_mode, 'stocked') = 'stocked'
     and coalesce(new.fulfillment_mode, 'stocked') = 'orderable'
     and coalesce(old.quantity_reserved, 0) > 0 then
    raise exception 'Cannot switch a reward to Available to order while prepared units are reserved.';
  end if;

  return new;
end;
$$;

drop trigger if exists sq_reward_inventory_validate on public.reward_items;
create trigger sq_reward_inventory_validate
before insert or update of quantity_total, quantity_reserved, fulfillment_mode
on public.reward_items
for each row execute function public.sq_validate_reward_inventory();

-- One central transition matrix prevents accidental status skipping and protects
-- against refunding an order after a Steam trade has already been sent.
create or replace function public.sq_order_transition_allowed(
  p_mode text,
  p_from text,
  p_to text
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_mode text := case when p_mode = 'orderable' then 'orderable' else 'stocked' end;
  v_from text := lower(coalesce(p_from, 'pending'));
  v_to text := lower(coalesce(p_to, ''));
begin
  if v_to = v_from then return true; end if;
  if v_from in ('completed','rejected','refunded','cancelled') then return false; end if;

  -- Once a trade has been sent, never refund/cancel from the normal order RPC.
  -- It can be moved back to Ready to trade if the Steam offer expires/is declined,
  -- or completed after acceptance.
  if v_from = 'trade_sent' then
    return v_to in ('ready_to_trade','completed');
  end if;

  if v_to in ('rejected','refunded','cancelled') then
    return true;
  end if;

  if v_mode = 'orderable' then
    return case v_from
      when 'pending' then v_to in ('reviewing','ordered')
      when 'reviewing' then v_to in ('pending','ordered')
      when 'ordered' then v_to = 'trade_locked'
      when 'trade_locked' then v_to = 'ready_to_trade'
      when 'ready_to_trade' then v_to = 'trade_sent'
      else false
    end;
  end if;

  return case v_from
    when 'pending' then v_to in ('reviewing','ready_to_trade')
    when 'reviewing' then v_to in ('pending','ready_to_trade')
    when 'ordered' then v_to = 'ready_to_trade'       -- legacy compatibility
    when 'trade_locked' then v_to = 'ready_to_trade'  -- legacy compatibility
    when 'ready_to_trade' then v_to = 'trade_sent'
    else false
  end;
end;
$$;

revoke all on function public.sq_order_transition_allowed(text,text,text) from public, anon;
grant execute on function public.sq_order_transition_allowed(text,text,text) to authenticated, service_role;

create or replace function public.sq_admin_update_order(
  p_request_id bigint,
  p_status text,
  p_admin_note text default null,
  p_trade_offer_url text default null,
  p_trade_locked_until timestamptz default null
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
  v_status text := lower(trim(coalesce(p_status, '')));
  v_note text := nullif(trim(coalesce(p_admin_note, '')), '');
  v_trade_offer_url text := nullif(trim(coalesce(p_trade_offer_url, '')), '');
  v_trade_locked_until timestamptz := p_trade_locked_until;
  v_cost integer;
  v_release_stock boolean := false;
  v_refund boolean := false;
  v_final_trade_url text;
  v_changed boolean := false;
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  if p_request_id is null or p_request_id < 1 then raise exception 'Invalid order.'; end if;
  if v_status not in ('pending','reviewing','ordered','trade_locked','ready_to_trade','trade_sent','completed','rejected','refunded','cancelled') then
    raise exception 'Invalid order status.';
  end if;
  if v_note is not null and length(v_note) > 2000 then raise exception 'Admin note is too long.'; end if;
  if v_trade_offer_url is not null and (
    length(v_trade_offer_url) > 500 or
    v_trade_offer_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/[0-9]+/?([?#].*)?$'
  ) then
    raise exception 'Enter a valid Steam trade-offer URL such as https://steamcommunity.com/tradeoffer/123456789/.';
  end if;

  select * into v_request from public.redemption_requests where id = p_request_id for update;
  if not found then raise exception 'Order not found.'; end if;

  v_old_status := lower(coalesce(v_request.status, 'pending'));
  v_final_trade_url := coalesce(v_trade_offer_url, v_request.trade_offer_url);

  if not public.sq_order_transition_allowed(v_request.fulfillment_mode, v_old_status, v_status) then
    raise exception 'Invalid order transition: % -> % for % fulfilment.', v_old_status, v_status, v_request.fulfillment_mode;
  end if;

  if v_status = 'trade_locked' then
    if v_request.fulfillment_mode <> 'orderable' then
      raise exception 'Only Available to order rewards can enter Trade locked.';
    end if;
    if v_trade_locked_until is null then v_trade_locked_until := v_request.trade_locked_until; end if;
    if v_trade_locked_until is null then raise exception 'Enter the Steam trade-lock end time.'; end if;
    if v_trade_locked_until <= now() then
      raise exception 'Trade-lock end time must be in the future. Use Ready to trade only after the lock has ended.';
    end if;
  end if;

  if v_status = 'completed' then
    if v_old_status <> 'trade_sent' then raise exception 'Mark the order Trade sent before completing it.'; end if;
  end if;

  v_cost := coalesce(nullif(v_request.points_coins, 0), v_request.points_cost, 0);
  if v_status in ('rejected','refunded','cancelled') and v_request.refunded_at is null then
    v_refund := true;
    v_release_stock := v_request.fulfillment_mode = 'stocked';
  elsif v_status = 'completed' and v_request.completed_at is null then
    v_release_stock := v_request.fulfillment_mode = 'stocked';
  end if;

  if v_refund then
    update public.profiles
      set points_balance = coalesce(points_balance, 0) + v_cost, updated_at = now()
      where id = v_request.user_id;
    insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, created_by, metadata)
    values (
      v_request.user_id, v_cost, 'Reward order refund / ' || v_request.reward_name,
      'redemption_refund', v_request.id::text, v_admin_id,
      jsonb_build_object('old_status',v_old_status,'new_status',v_status,'fulfillment_mode',v_request.fulfillment_mode)
    );
  end if;

  if v_release_stock and v_request.reward_id is not null then
    if v_status = 'completed' then
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved,0) - 1),
          quantity_total = greatest(0, coalesce(quantity_total,0) - 1), updated_at = now()
      where id = v_request.reward_id;
    else
      update public.reward_items
      set quantity_reserved = greatest(0, coalesce(quantity_reserved,0) - 1), updated_at = now()
      where id = v_request.reward_id;
    end if;
  end if;

  v_changed := v_status is distinct from v_old_status
    or v_request.admin_note is distinct from v_note
    or v_request.trade_offer_url is distinct from v_final_trade_url
    or (v_status = 'trade_locked' and v_request.trade_locked_until is distinct from v_trade_locked_until);

  update public.redemption_requests
  set status = v_status,
      admin_note = v_note,
      trade_offer_url = v_final_trade_url,
      purchased_at = case when v_status = 'trade_locked' then coalesce(purchased_at, now()) else purchased_at end,
      trade_locked_until = case when v_status = 'trade_locked' then v_trade_locked_until else trade_locked_until end,
      estimated_ready_at = case when v_status = 'trade_locked' then v_trade_locked_until else estimated_ready_at end,
      ready_at = case when v_status = 'ready_to_trade' then coalesce(ready_at, now()) else ready_at end,
      trade_sent_at = case when v_status = 'trade_sent' then now() else trade_sent_at end,
      refunded_at = case when v_refund then now() else refunded_at end,
      completed_at = case when v_status = 'completed' then coalesce(completed_at, now()) else completed_at end,
      completed_by = case when v_status = 'completed' then coalesce(completed_by, v_admin_id) else completed_by end,
      last_handled_by = v_admin_id,
      last_handled_at = now(),
      updated_at = now()
  where id = p_request_id;

  if v_changed then
    insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
    values (
      v_admin_id, 'redemption_status_update', 'redemption_request', p_request_id::text,
      jsonb_build_object(
        'order_number',v_request.order_number,'fulfillment_mode',v_request.fulfillment_mode,
        'from_status',v_old_status,'to_status',v_status,'trade_locked_until',v_trade_locked_until,
        'note_changed',v_request.admin_note is distinct from v_note,
        'trade_proof_changed',v_request.trade_offer_url is distinct from v_final_trade_url,
        'refunded',v_refund
      )
    );
  end if;

  return jsonb_build_object('ok',true,'request_id',p_request_id,'order_number',v_request.order_number,
    'status',v_status,'refunded',v_refund,'trade_locked_until',v_trade_locked_until);
end;
$$;

revoke all on function public.sq_admin_update_order(bigint,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.sq_admin_update_order(bigint,text,text,text,timestamptz) to authenticated;

-- Compatibility wrapper still routes old cached Admin clients through the same rules.
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
begin
  return public.sq_admin_update_order(p_request_id,p_status,p_admin_note,p_trade_offer_url,null);
end;
$$;

revoke all on function public.admin_update_redemption_status(bigint,text,text,text) from public, anon, authenticated;
grant execute on function public.admin_update_redemption_status(bigint,text,text,text) to authenticated;

-- Service-safe sweep used by the scheduled Edge Function. Admins may also run it
-- manually from the workspace. It never touches non-expired locks.
create or replace function public.sq_refresh_expired_trade_locks(p_limit integer default 100)
returns table(request_id bigint, order_number text, user_id uuid, reward_name text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean := public.is_admin() or auth.role() = 'service_role';
  v_row record;
begin
  if not v_allowed then raise exception 'Admin or service access required.'; end if;
  for v_row in
    select r.id, r.order_number, r.user_id, r.reward_name
    from public.redemption_requests r
    where r.status = 'trade_locked' and r.trade_locked_until is not null and r.trade_locked_until <= now()
    order by r.trade_locked_until asc
    for update skip locked
    limit greatest(1, least(coalesce(p_limit,100),500))
  loop
    update public.redemption_requests
      set status='ready_to_trade', ready_at=coalesce(ready_at,now()), updated_at=now()
      where id=v_row.id and status='trade_locked';
    if found then
      insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
      values (auth.uid(),'trade_lock_expired','redemption_request',v_row.id::text,
        jsonb_build_object('order_number',v_row.order_number,'to_status','ready_to_trade','automatic',auth.role()='service_role'));
      request_id := v_row.id; order_number := v_row.order_number; user_id := v_row.user_id; reward_name := v_row.reward_name;
      return next;
    end if;
  end loop;
end;
$$;

revoke all on function public.sq_refresh_expired_trade_locks(integer) from public, anon, authenticated;
grant execute on function public.sq_refresh_expired_trade_locks(integer) to authenticated, service_role;

-- Keep old no-argument admin RPC compatible while routing through the new sweep.
create or replace function public.sq_admin_refresh_trade_locks()
returns table(request_id bigint, order_number text)
language sql
security definer
set search_path = public
as $$
  select x.request_id, x.order_number
  from public.sq_refresh_expired_trade_locks(100) x;
$$;
revoke all on function public.sq_admin_refresh_trade_locks() from public, anon, authenticated;
grant execute on function public.sq_admin_refresh_trade_locks() to authenticated;

commit;
notify pgrst, 'reload schema';
-- End of v14.4.1 hardening.

-- =============================================================================
-- Integrated v14.5.0 Steam catalog and automatic pricing layer
-- =============================================================================
begin;

-- =============================================================================
-- 1. Steam-linked reward pricing and catalog metadata
-- =============================================================================

alter table public.reward_items add column if not exists pricing_mode text not null default 'manual';
alter table public.reward_items add column if not exists manual_price_override boolean not null default false;
alter table public.reward_items add column if not exists steam_price_minor integer;
alter table public.reward_items add column if not exists steam_price_currency text not null default 'EUR';
alter table public.reward_items add column if not exists steam_price_updated_at timestamptz;
alter table public.reward_items add column if not exists steam_price_valid_until timestamptz;
alter table public.reward_items add column if not exists steam_listing_count integer;
alter table public.reward_items add column if not exists catalog_managed boolean not null default false;
alter table public.reward_items add column if not exists catalog_last_seen_at timestamptz;

do $$
begin
  alter table public.reward_items
    add constraint reward_items_pricing_mode_check
    check (pricing_mode in ('manual', 'steam'));
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.reward_items
    add constraint reward_items_steam_price_minor_check
    check (steam_price_minor is null or steam_price_minor > 0);
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.reward_items
    add constraint reward_items_steam_listing_count_check
    check (steam_listing_count is null or steam_listing_count >= 0);
exception when duplicate_object then null;
end $$;

create index if not exists reward_items_catalog_search_idx
  on public.reward_items (active, fulfillment_mode, pricing_mode, points_coins, id);
create index if not exists reward_items_market_name_lower_idx
  on public.reward_items (lower(market_name)) where market_name is not null;
create index if not exists reward_items_catalog_seen_idx
  on public.reward_items (catalog_managed, catalog_last_seen_at) where catalog_managed = true;

create table if not exists public.sq_reward_pricing_settings (
  id smallint primary key default 1 check (id = 1),
  markup_percent numeric(7,2) not null default 15.00 check (markup_percent between 0 and 500),
  coins_per_eur numeric(12,2) not null default 100.00 check (coins_per_eur between 0.01 and 100000),
  minimum_coin_price integer not null default 1 check (minimum_coin_price between 1 and 1000000),
  max_price_age_hours integer not null default 48 check (max_price_age_hours between 1 and 168),
  catalog_auto_publish boolean not null default true,
  catalog_default_eta_days integer not null default 8 check (catalog_default_eta_days between 7 and 30),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.sq_reward_pricing_settings (id)
values (1)
on conflict (id) do nothing;

drop trigger if exists sq_reward_pricing_settings_updated_at on public.sq_reward_pricing_settings;
create trigger sq_reward_pricing_settings_updated_at
before update on public.sq_reward_pricing_settings
for each row execute function public.set_updated_at();

create table if not exists public.sq_steam_catalog_sync_state (
  id smallint primary key default 1 check (id = 1),
  next_start integer not null default 0 check (next_start >= 0),
  total_count integer not null default 0 check (total_count >= 0),
  cycle_started_at timestamptz,
  last_run_at timestamptz,
  last_completed_at timestamptz,
  last_error text,
  cycle_results_scanned integer not null default 0,
  cycle_eligible_items integer not null default 0,
  last_batch_created integer not null default 0,
  last_batch_updated integer not null default 0,
  updated_at timestamptz not null default now()
);

insert into public.sq_steam_catalog_sync_state (id)
values (1)
on conflict (id) do nothing;

alter table public.sq_reward_pricing_settings enable row level security;
alter table public.sq_steam_catalog_sync_state enable row level security;

drop policy if exists sq_reward_pricing_settings_admin_select on public.sq_reward_pricing_settings;
create policy sq_reward_pricing_settings_admin_select
on public.sq_reward_pricing_settings for select to authenticated
using (public.is_admin());

drop policy if exists sq_steam_catalog_sync_state_admin_select on public.sq_steam_catalog_sync_state;
create policy sq_steam_catalog_sync_state_admin_select
on public.sq_steam_catalog_sync_state for select to authenticated
using (public.is_admin());

revoke all on table public.sq_reward_pricing_settings from public, anon, authenticated;
revoke all on table public.sq_steam_catalog_sync_state from public, anon, authenticated;
grant select on table public.sq_reward_pricing_settings to authenticated;
grant select on table public.sq_steam_catalog_sync_state to authenticated;

-- One deterministic formula is used by imports, individual edits, and global
-- markup changes. Steam's EUR amount is stored in cents; customer orders store
-- the resulting coin price as an immutable snapshot.
create or replace function public.sq_reward_coin_price(p_steam_price_minor integer)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select least(
    2147483647::numeric,
    greatest(
      s.minimum_coin_price::numeric,
      ceil(
        (greatest(coalesce(p_steam_price_minor, 0), 0)::numeric / 100.0)
        * s.coins_per_eur
        * (1.0 + (s.markup_percent / 100.0))
      )
    )
  )::integer
  from public.sq_reward_pricing_settings s
  where s.id = 1;
$$;

revoke all on function public.sq_reward_coin_price(integer) from public, anon;
grant execute on function public.sq_reward_coin_price(integer) to authenticated, service_role;

create or replace function public.sq_apply_reward_steam_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max_age integer;
begin
  if new.pricing_mode = 'steam' then
    if nullif(trim(coalesce(new.market_name, '')), '') is null then
      new.market_name := nullif(trim(coalesce(new.name, '')), '');
    end if;
    new.steam_price_currency := 'EUR';

    if coalesce(new.steam_price_minor, 0) > 0 then
      new.points_coins := public.sq_reward_coin_price(new.steam_price_minor);
      new.points_cost := new.points_coins;
      select max_price_age_hours into v_max_age
      from public.sq_reward_pricing_settings where id = 1;
      if new.steam_price_updated_at is not null then
        new.steam_price_valid_until := new.steam_price_updated_at
          + make_interval(hours => coalesce(v_max_age, 48));
      end if;
    else
      new.steam_price_valid_until := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists zz_reward_items_apply_steam_price on public.reward_items;
create trigger zz_reward_items_apply_steam_price
before insert or update of pricing_mode, market_name, steam_price_minor, steam_price_updated_at, points_coins, points_cost
on public.reward_items
for each row execute function public.sq_apply_reward_steam_price();

-- Avoid thousands of low-value audit rows during a global recalculation while
-- preserving a detailed audit event for individual reward edits.
create or replace function public.sq_audit_reward_item()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('skinquest.bulk_reward_pricing', true) = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if public.sq_is_admin() then
    insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
    values(
      auth.uid(),
      lower(tg_op),
      'reward_item',
      coalesce(new.id, old.id)::text,
      jsonb_build_object(
        'name', coalesce(new.name, old.name),
        'fulfillment_before', case when tg_op = 'INSERT' then null else old.fulfillment_mode end,
        'fulfillment_after', case when tg_op = 'DELETE' then null else new.fulfillment_mode end,
        'pricing_before', case when tg_op = 'INSERT' then null else old.pricing_mode end,
        'pricing_after', case when tg_op = 'DELETE' then null else new.pricing_mode end,
        'price_before', case when tg_op = 'INSERT' then null else old.points_coins end,
        'price_after', case when tg_op = 'DELETE' then null else new.points_coins end,
        'order_eta_before', case when tg_op = 'INSERT' then null else old.order_eta_days end,
        'order_eta_after', case when tg_op = 'DELETE' then null else new.order_eta_days end,
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

-- A stale Steam price is rejected in the database. If this trigger raises, the
-- entire redeem_reward transaction (coin debit and stock reservation included)
-- rolls back, so the customer cannot lose coins on a stale listing.
create or replace function public.sq_require_current_reward_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pricing_mode text;
  v_price integer;
  v_valid_until timestamptz;
begin
  if new.reward_id is null then return new; end if;

  select pricing_mode, steam_price_minor, steam_price_valid_until
  into v_pricing_mode, v_price, v_valid_until
  from public.reward_items
  where id = new.reward_id;

  if v_pricing_mode = 'steam' and (
    coalesce(v_price, 0) <= 0 or v_valid_until is null or v_valid_until <= now()
  ) then
    raise exception 'Steam price is refreshing. No coins were deducted; try again after the next catalog sync.';
  end if;
  return new;
end;
$$;

drop trigger if exists sq_redemption_require_current_price on public.redemption_requests;
create trigger sq_redemption_require_current_price
before insert on public.redemption_requests
for each row execute function public.sq_require_current_reward_price();

-- =============================================================================
-- 2. Owner pricing controls
-- =============================================================================

create or replace function public.sq_admin_update_reward_pricing_settings(
  p_markup_percent numeric,
  p_coins_per_eur numeric,
  p_minimum_coin_price integer,
  p_max_price_age_hours integer,
  p_catalog_auto_publish boolean,
  p_catalog_default_eta_days integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_after jsonb;
begin
  if not public.is_owner() then raise exception 'Owner access required.'; end if;
  if p_markup_percent is null or p_markup_percent < 0 or p_markup_percent > 500 then raise exception 'Markup must be between 0 and 500 percent.'; end if;
  if p_coins_per_eur is null or p_coins_per_eur < 0.01 or p_coins_per_eur > 100000 then raise exception 'Coins per EUR is outside the allowed range.'; end if;
  if p_minimum_coin_price is null or p_minimum_coin_price < 1 or p_minimum_coin_price > 1000000 then raise exception 'Minimum coin price is outside the allowed range.'; end if;
  if p_max_price_age_hours is null or p_max_price_age_hours < 1 or p_max_price_age_hours > 168 then raise exception 'Price validity must be between 1 and 168 hours.'; end if;
  if p_catalog_default_eta_days is null or p_catalog_default_eta_days < 7 or p_catalog_default_eta_days > 30 then raise exception 'Default order ETA must be between 7 and 30 days.'; end if;

  select to_jsonb(s) into v_before
  from public.sq_reward_pricing_settings s where id = 1 for update;

  update public.sq_reward_pricing_settings
  set markup_percent = round(p_markup_percent, 2),
      coins_per_eur = round(p_coins_per_eur, 2),
      minimum_coin_price = p_minimum_coin_price,
      max_price_age_hours = p_max_price_age_hours,
      catalog_auto_publish = coalesce(p_catalog_auto_publish, true),
      catalog_default_eta_days = p_catalog_default_eta_days,
      updated_by = auth.uid()
  where id = 1;

  perform set_config('skinquest.bulk_reward_pricing', 'on', true);
  update public.reward_items
  set points_coins = public.sq_reward_coin_price(steam_price_minor),
      points_cost = public.sq_reward_coin_price(steam_price_minor),
      steam_price_valid_until = steam_price_updated_at + make_interval(hours => p_max_price_age_hours)
  where pricing_mode = 'steam' and coalesce(steam_price_minor, 0) > 0;
  perform set_config('skinquest.bulk_reward_pricing', 'off', true);

  select to_jsonb(s) into v_after
  from public.sq_reward_pricing_settings s where id = 1;

  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values(
    auth.uid(), 'reward_pricing_settings_update', 'reward_pricing_settings', '1',
    jsonb_build_object(
      'before', v_before,
      'after', v_after,
      'markup_percent', p_markup_percent,
      'coins_per_eur', p_coins_per_eur,
      'minimum_coin_price', p_minimum_coin_price,
      'max_price_age_hours', p_max_price_age_hours
    )
  );
  return v_after;
end;
$$;

revoke all on function public.sq_admin_update_reward_pricing_settings(numeric,numeric,integer,integer,boolean,integer) from public, anon, authenticated;
grant execute on function public.sq_admin_update_reward_pricing_settings(numeric,numeric,integer,integer,boolean,integer) to authenticated;

-- =============================================================================
-- 3. Paginated customer/admin catalog queries
-- =============================================================================

create or replace function public.sq_search_rewards(
  p_query text default null,
  p_min_coins integer default null,
  p_max_coins integer default null,
  p_availability text default 'all',
  p_balance integer default 0,
  p_sort text default 'price-desc',
  p_show_out_of_stock boolean default true,
  p_limit integer default 48,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := left(lower(trim(coalesce(p_query, ''))), 120);
  v_availability text := lower(coalesce(p_availability, 'all'));
  v_sort text := lower(coalesce(p_sort, 'price-desc'));
  v_limit integer := greatest(1, least(coalesce(p_limit, 48), 60));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  if v_availability not in ('all', 'affordable', 'in-stock', 'orderable') then v_availability := 'all'; end if;
  if v_sort not in ('price-asc', 'price-desc', 'featured', 'stock-desc', 'name-asc') then v_sort := 'price-desc'; end if;

  return (
    with filtered as (
      select r.*,
             greatest(0, coalesce(r.quantity_total, 0) - coalesce(r.quantity_reserved, 0)) as sq_available_stock,
             case when r.fulfillment_mode = 'stocked'
                       and greatest(0, coalesce(r.quantity_total, 0) - coalesce(r.quantity_reserved, 0)) <= 0
                  then 1 else 0 end as sq_out_of_stock
      from public.reward_items r
      where r.active = true
        and (
          v_query = '' or lower(coalesce(r.name, '')) like '%' || v_query || '%'
          or lower(coalesce(r.market_name, '')) like '%' || v_query || '%'
          or lower(coalesce(r.description, '')) like '%' || v_query || '%'
          or lower(coalesce(r.rarity, '')) like '%' || v_query || '%'
          or lower(coalesce(r.condition, '')) like '%' || v_query || '%'
        )
        and (p_min_coins is null or r.points_coins >= greatest(0, p_min_coins))
        and (p_max_coins is null or r.points_coins <= greatest(0, p_max_coins))
        and (
          coalesce(p_show_out_of_stock, true)
          or r.fulfillment_mode = 'orderable'
          or greatest(0, coalesce(r.quantity_total, 0) - coalesce(r.quantity_reserved, 0)) > 0
        )
        and (
          v_availability = 'all'
          or (v_availability = 'affordable'
              and r.points_coins <= greatest(0, coalesce(p_balance, 0))
              and (r.fulfillment_mode = 'orderable' or greatest(0, coalesce(r.quantity_total, 0) - coalesce(r.quantity_reserved, 0)) > 0))
          or (v_availability = 'in-stock'
              and r.fulfillment_mode = 'stocked'
              and greatest(0, coalesce(r.quantity_total, 0) - coalesce(r.quantity_reserved, 0)) > 0)
          or (v_availability = 'orderable' and r.fulfillment_mode = 'orderable')
        )
    ), ordered as (
      select f.*,
             row_number() over (order by
               f.sq_out_of_stock asc,
               case when v_sort = 'price-asc' then f.points_coins end asc nulls last,
               case when v_sort = 'price-desc' then f.points_coins end desc nulls last,
               case when v_sort = 'stock-desc' then case when f.fulfillment_mode = 'stocked' then f.sq_available_stock else -1 end end desc nulls last,
               case when v_sort = 'featured' then f.sort_order end asc nulls last,
               case when v_sort = 'name-asc' then lower(f.name) end asc nulls last,
               lower(f.name) asc,
               f.id asc
             ) as sq_row_number
      from filtered f
    ), page as (
      select * from ordered
      where sq_row_number > v_offset and sq_row_number <= v_offset + v_limit
    )
    select jsonb_build_object(
      'items', coalesce((
        select jsonb_agg(
          (to_jsonb(p) - 'sq_row_number' - 'sq_available_stock' - 'sq_out_of_stock')
          || jsonb_build_object(
            'available_stock', p.sq_available_stock,
            'price_is_current', p.pricing_mode <> 'steam' or (
              coalesce(p.steam_price_minor, 0) > 0
              and p.steam_price_valid_until is not null
              and p.steam_price_valid_until > now()
            )
          ) order by p.sq_row_number
        ) from page p
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'limit', v_limit,
      'offset', v_offset
    )
  );
end;
$$;

revoke all on function public.sq_search_rewards(text,integer,integer,text,integer,text,boolean,integer,integer) from public;
grant execute on function public.sq_search_rewards(text,integer,integer,text,integer,text,boolean,integer,integer) to anon, authenticated;

create or replace function public.sq_admin_search_reward_items(
  p_query text default null,
  p_filter text default 'all',
  p_limit integer default 75,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := left(lower(trim(coalesce(p_query, ''))), 120);
  v_filter text := lower(coalesce(p_filter, 'all'));
  v_limit integer := greatest(1, least(coalesce(p_limit, 75), 150));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  if v_filter not in ('all', 'stocked', 'orderable', 'steam', 'stale', 'inactive') then v_filter := 'all'; end if;

  return (
    with filtered as (
      select r.*
      from public.reward_items r
      where (
          v_query = '' or lower(coalesce(r.name, '')) like '%' || v_query || '%'
          or lower(coalesce(r.market_name, '')) like '%' || v_query || '%'
          or lower(coalesce(r.rarity, '')) like '%' || v_query || '%'
          or lower(coalesce(r.condition, '')) like '%' || v_query || '%'
        )
        and (
          v_filter = 'all'
          or (v_filter = 'stocked' and r.fulfillment_mode = 'stocked')
          or (v_filter = 'orderable' and r.fulfillment_mode = 'orderable')
          or (v_filter = 'steam' and r.pricing_mode = 'steam')
          or (v_filter = 'stale' and r.pricing_mode = 'steam' and (
                coalesce(r.steam_price_minor, 0) <= 0 or r.steam_price_valid_until is null or r.steam_price_valid_until <= now()
              ))
          or (v_filter = 'inactive' and r.active = false)
        )
    ), ordered as (
      select f.*, row_number() over (order by
        f.active desc,
        case when f.fulfillment_mode = 'stocked' then 0 else 1 end,
        f.sort_order asc,
        lower(f.name) asc,
        f.id asc
      ) as sq_row_number
      from filtered f
    ), page as (
      select * from ordered
      where sq_row_number > v_offset and sq_row_number <= v_offset + v_limit
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(to_jsonb(p) - 'sq_row_number' order by p.sq_row_number) from page p), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'limit', v_limit,
      'offset', v_offset
    )
  );
end;
$$;

revoke all on function public.sq_admin_search_reward_items(text,text,integer,integer) from public, anon, authenticated;
grant execute on function public.sq_admin_search_reward_items(text,text,integer,integer) to authenticated;

create or replace function public.sq_admin_reward_pricing_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  return jsonb_build_object(
    'settings', coalesce((select to_jsonb(s) from public.sq_reward_pricing_settings s where id = 1), '{}'::jsonb),
    'sync', coalesce((select to_jsonb(c) from public.sq_steam_catalog_sync_state c where id = 1), '{}'::jsonb),
    'stats', jsonb_build_object(
      'active_listings', (select count(*) from public.reward_items where active = true),
      'orderable_listings', (select count(*) from public.reward_items where active = true and fulfillment_mode = 'orderable'),
      'prepared_units', (select coalesce(sum(greatest(0, quantity_total - quantity_reserved)), 0) from public.reward_items where fulfillment_mode = 'stocked'),
      'reserved_units', (select coalesce(sum(greatest(0, quantity_reserved)), 0) from public.reward_items where fulfillment_mode = 'stocked'),
      'steam_linked', (select count(*) from public.reward_items where pricing_mode = 'steam'),
      'stale_prices', (select count(*) from public.reward_items where active = true and pricing_mode = 'steam' and (
        coalesce(steam_price_minor, 0) <= 0 or steam_price_valid_until is null or steam_price_valid_until <= now()
      )),
      'catalog_items', (select count(*) from public.reward_items where catalog_managed = true)
    )
  );
end;
$$;

revoke all on function public.sq_admin_reward_pricing_dashboard() from public, anon, authenticated;
grant execute on function public.sq_admin_reward_pricing_dashboard() to authenticated;

-- =============================================================================
-- 4. Service-only, resumable Steam catalog import
-- =============================================================================

create or replace function public.sq_service_apply_steam_catalog_batch(
  p_items jsonb,
  p_start integer,
  p_next_start integer,
  p_total_count integer,
  p_results_scanned integer,
  p_completed boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.sq_reward_pricing_settings%rowtype;
  v_sync public.sq_steam_catalog_sync_state%rowtype;
  v_item jsonb;
  v_market_name text;
  v_image_url text;
  v_description text;
  v_rarity text;
  v_condition text;
  v_price_text text;
  v_listings_text text;
  v_price integer;
  v_listings integer;
  v_existing_id bigint;
  v_created integer := 0;
  v_updated integer := 0;
  v_eligible integer := 0;
  v_cycle_started_at timestamptz;
  v_now timestamptz := clock_timestamp();
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'Catalog items must be a JSON array.'; end if;

  select * into v_settings from public.sq_reward_pricing_settings where id = 1;
  insert into public.sq_steam_catalog_sync_state(id) values (1) on conflict (id) do nothing;
  select * into v_sync from public.sq_steam_catalog_sync_state where id = 1 for update;
  v_cycle_started_at := case
    when greatest(0, coalesce(p_start, 0)) = 0 or v_sync.cycle_started_at is null then v_now
    else v_sync.cycle_started_at
  end;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_market_name := left(trim(coalesce(v_item->>'market_name', '')), 240);
    v_image_url := nullif(left(trim(coalesce(v_item->>'image_url', '')), 500), '');
    v_description := nullif(left(trim(coalesce(v_item->>'description', '')), 500), '');
    v_rarity := nullif(left(lower(trim(coalesce(v_item->>'rarity', ''))), 40), '');
    v_condition := nullif(left(trim(coalesce(v_item->>'condition', '')), 40), '');
    v_price_text := coalesce(v_item->>'steam_price_minor', '');
    v_listings_text := coalesce(v_item->>'steam_listing_count', '');
    v_price := case when v_price_text ~ '^[0-9]{1,10}$' then least(v_price_text::numeric, 2147483647)::integer else 0 end;
    v_listings := case when v_listings_text ~ '^[0-9]{1,10}$' then least(v_listings_text::numeric, 2147483647)::integer else 0 end;

    if v_market_name = '' or v_price <= 0 then continue; end if;
    v_eligible := v_eligible + 1;

    select r.id into v_existing_id
    from public.reward_items r
    where lower(coalesce(r.market_name, '')) = lower(v_market_name)
       or (r.market_name is null and lower(trim(r.name)) = lower(v_market_name))
    order by case when lower(coalesce(r.market_name, '')) = lower(v_market_name) then 0 else 1 end, r.id
    limit 1
    for update;

    if v_existing_id is null then
      insert into public.reward_items(
        name, market_name, description, image_url, rarity, condition,
        points_coins, points_cost, quantity_total, quantity_reserved,
        active, sort_order, fulfillment_mode, order_eta_days,
        pricing_mode, manual_price_override, steam_price_minor,
        steam_price_currency, steam_price_updated_at, steam_price_valid_until,
        steam_listing_count, catalog_managed, catalog_last_seen_at
      ) values (
        v_market_name, v_market_name, v_description, v_image_url, v_rarity, v_condition,
        public.sq_reward_coin_price(v_price), public.sq_reward_coin_price(v_price), 0, 0,
        v_settings.catalog_auto_publish, 0, 'orderable', v_settings.catalog_default_eta_days,
        'steam', false, v_price, 'EUR', v_now,
        v_now + make_interval(hours => v_settings.max_price_age_hours),
        v_listings, true, v_now
      );
      v_created := v_created + 1;
    else
      update public.reward_items r
      set name = case when r.catalog_managed then v_market_name else r.name end,
          market_name = v_market_name,
          description = case when r.catalog_managed or nullif(trim(coalesce(r.description, '')), '') is null then coalesce(v_description, r.description) else r.description end,
          image_url = case when r.catalog_managed or nullif(trim(coalesce(r.image_url, '')), '') is null then coalesce(v_image_url, r.image_url) else r.image_url end,
          rarity = case when r.catalog_managed or nullif(trim(coalesce(r.rarity, '')), '') is null then coalesce(v_rarity, r.rarity) else r.rarity end,
          condition = case when r.catalog_managed or nullif(trim(coalesce(r.condition, '')), '') is null then coalesce(v_condition, r.condition) else r.condition end,
          pricing_mode = case when r.manual_price_override then 'manual' else 'steam' end,
          steam_price_minor = v_price,
          steam_price_currency = 'EUR',
          steam_price_updated_at = v_now,
          steam_price_valid_until = v_now + make_interval(hours => v_settings.max_price_age_hours),
          steam_listing_count = v_listings,
          catalog_last_seen_at = v_now
      where r.id = v_existing_id;
      v_updated := v_updated + 1;
    end if;
    v_existing_id := null;
  end loop;

  if coalesce(p_completed, false) then
    perform set_config('skinquest.bulk_reward_pricing', 'on', true);
    update public.reward_items
    set active = false
    where catalog_managed = true
      and active = true
      and fulfillment_mode = 'orderable'
      and coalesce(quantity_total, 0) = 0
      and (catalog_last_seen_at is null or catalog_last_seen_at < v_cycle_started_at);
    perform set_config('skinquest.bulk_reward_pricing', 'off', true);
  end if;

  update public.sq_steam_catalog_sync_state
  set next_start = case when coalesce(p_completed, false) then 0 else greatest(0, coalesce(p_next_start, 0)) end,
      total_count = greatest(0, coalesce(p_total_count, 0)),
      cycle_started_at = case when coalesce(p_completed, false) then null else v_cycle_started_at end,
      last_run_at = v_now,
      last_completed_at = case when coalesce(p_completed, false) then v_now else last_completed_at end,
      last_error = null,
      cycle_results_scanned = case when greatest(0, coalesce(p_start, 0)) = 0 then greatest(0, coalesce(p_results_scanned, 0)) else cycle_results_scanned + greatest(0, coalesce(p_results_scanned, 0)) end,
      cycle_eligible_items = case when greatest(0, coalesce(p_start, 0)) = 0 then v_eligible else cycle_eligible_items + v_eligible end,
      last_batch_created = v_created,
      last_batch_updated = v_updated,
      updated_at = v_now
  where id = 1;

  return jsonb_build_object(
    'created', v_created,
    'updated', v_updated,
    'eligible', v_eligible,
    'next_start', case when coalesce(p_completed, false) then 0 else greatest(0, coalesce(p_next_start, 0)) end,
    'total_count', greatest(0, coalesce(p_total_count, 0)),
    'completed', coalesce(p_completed, false)
  );
end;
$$;

revoke all on function public.sq_service_apply_steam_catalog_batch(jsonb,integer,integer,integer,integer,boolean) from public, anon, authenticated;
grant execute on function public.sq_service_apply_steam_catalog_batch(jsonb,integer,integer,integer,integer,boolean) to service_role;

create or replace function public.sq_service_record_steam_sync_error(p_error text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required.'; end if;
  update public.sq_steam_catalog_sync_state
  set last_error = left(coalesce(nullif(trim(p_error), ''), 'Unknown Steam sync error.'), 1000),
      last_run_at = now(),
      updated_at = now()
  where id = 1;
end;
$$;

revoke all on function public.sq_service_record_steam_sync_error(text) from public, anon, authenticated;
grant execute on function public.sq_service_record_steam_sync_error(text) to service_role;

commit;

notify pgrst, 'reload schema';

-- End of v14.5.0-only upgrade.

-- v14.5.1 achievement event-date repair.
begin;
-- Record the event time separately from when a progress refresh discovered it.
-- Missing historical evidence stays NULL; never claim a guessed unlock date.
alter table public.sq_user_achievements
  add column if not exists earned_at timestamptz;

create or replace function public.sq_achievement_event_at(p_user_id uuid, p_key text)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_at timestamptz;
begin
  if p_key = 'first_earn' then
    select min(c.created_at) into v_at from public.coin_adjustments c
    where c.user_id = p_user_id and c.amount > 0
      and coalesce(c.source_type, '') not in ('redemption_refund','admin_adjustment')
      and lower(coalesce(c.reason, '')) not like 'level reward%'
      and lower(coalesce(c.reason, '')) not like 'promo code%'
      and lower(coalesce(c.reason, '')) not like 'referral reward%'
      and lower(coalesce(c.reason, '')) not like 'manual admin%';
  elsif p_key = 'goal_set' then
    select min(f.created_at) into v_at from public.favorite_rewards f
    where f.user_id = p_user_id;
  elsif p_key = 'first_redeem' then
    select min(r.created_at) into v_at from public.redemption_requests r
    where r.user_id = p_user_id;
  elsif p_key = 'first_completed' then
    select min(r.completed_at) into v_at from public.redemption_requests r
    where r.user_id = p_user_id and r.status = 'completed';
  elsif p_key = 'collector_5' then
    select r.completed_at into v_at from public.redemption_requests r
    where r.user_id = p_user_id and r.status = 'completed'
      and r.completed_at is not null
    order by r.completed_at, r.id offset 4 limit 1;
    -- If some of the five completions lack trustworthy timestamps, do not
    -- mistake the fifth timestamped completion for the fifth overall.
    if (select count(*) from public.redemption_requests r
        where r.user_id = p_user_id and r.status = 'completed'
          and r.completed_at is null) > 0 then
      v_at := null;
    end if;
  elsif p_key = 'earned_1000' then
    select min(t.created_at) into v_at from (
      select c.created_at,
        sum(c.amount) over (order by c.created_at, c.id) as earned_total
      from public.coin_adjustments c
      where c.user_id = p_user_id and c.amount > 0
        and coalesce(c.source_type, '') not in ('redemption_refund','admin_adjustment')
        and lower(coalesce(c.reason, '')) not like 'level reward%'
        and lower(coalesce(c.reason, '')) not like 'promo code%'
        and lower(coalesce(c.reason, '')) not like 'referral reward%'
        and lower(coalesce(c.reason, '')) not like 'manual admin%'
    ) t where t.earned_total >= 1000;
  elsif p_key in ('streak_3', 'streak_7') then
    select min(d.first_seen_at) into v_at
    from public.sq_daily_activity d
    where d.user_id = p_user_id
      and (select count(*) from public.sq_daily_activity prev
           where prev.user_id = p_user_id
             and prev.activity_date between d.activity_date -
               (case when p_key = 'streak_7' then 6 else 2 end)
               and d.activity_date) =
               (case when p_key = 'streak_7' then 7 else 3 end);
  end if;
  return v_at;
end;
$$;

revoke all on function public.sq_achievement_event_at(uuid,text) from public, anon, authenticated;
-- Insertions from trusted progress functions also compute their source date.
create or replace function public.sq_set_achievement_earned_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.earned_at := public.sq_achievement_event_at(new.user_id, new.achievement_key);
  return new;
end;
$$;

revoke all on function public.sq_set_achievement_earned_at() from public, anon, authenticated;
drop trigger if exists sq_achievement_event_date on public.sq_user_achievements;
create trigger sq_achievement_event_date
before insert on public.sq_user_achievements
for each row execute function public.sq_set_achievement_earned_at();

-- Correct previously unlocked achievements only where the original event can
-- be determined. An unknown date remains blank in the interface.
update public.sq_user_achievements ua
set earned_at = public.sq_achievement_event_at(ua.user_id, ua.achievement_key);

commit;

notify pgrst, 'reload schema';

-- v14.5.2 admin user search and protected deletion controls.
begin;

-- Search the customer directory without exposing Steam placeholder emails.
create or replace function public.sq_admin_search_users(
  p_query text default null,
  p_limit integer default 75,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, auth
as $$
declare
  v_query text := left(trim(coalesce(p_query, '')), 120);
  v_limit integer := greatest(1, least(coalesce(p_limit, 75), 200));
  v_offset integer := greatest(0, least(coalesce(p_offset, 0), 100000));
  v_total integer;
  v_items jsonb;
begin
  if not public.is_admin() then
    raise exception 'Admin access required.';
  end if;

  select count(*) into v_total
  from public.profiles p
  left join auth.users u on u.id = p.id
  where v_query = ''
     or p.id::text ilike '%' || v_query || '%'
     or coalesce(p.username, '') ilike '%' || v_query || '%'
     or coalesce(p.steam_name, '') ilike '%' || v_query || '%'
     or coalesce(p.steam_id, '') ilike '%' || v_query || '%'
     or (p.contact_email_verified_at is not null and coalesce(p.contact_email, '') ilike '%' || v_query || '%')
     or (coalesce(u.email, '') not ilike '%@steam.skinquestcs.com' and coalesce(u.email, '') ilike '%' || v_query || '%');

  select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.created_at desc, row_data.user_id), '[]'::jsonb)
  into v_items
  from (
    select
      p.id as user_id,
      case when coalesce(u.email, '') ilike '%@steam.skinquestcs.com' then null else u.email::text end as email,
      p.username,
      p.steam_name,
      p.steam_id,
      case when p.contact_email_verified_at is not null then p.contact_email else null end as contact_email,
      p.contact_email_verified_at,
      coalesce(p.points_balance, 0) as points_balance,
      coalesce(p.account_status, 'active') as account_status,
      p.created_at,
      coalesce(order_stats.order_count, 0)::integer as order_count,
      coalesce(order_stats.completed_count, 0)::integer as completed_count,
      coalesce(support_stats.support_count, 0)::integer as support_count
    from public.profiles p
    left join auth.users u on u.id = p.id
    left join lateral (
      select count(*) as order_count,
             count(*) filter (where r.status = 'completed') as completed_count
      from public.redemption_requests r
      where r.user_id = p.id
    ) order_stats on true
    left join lateral (
      select count(*) as support_count
      from public.support_requests s
      where s.user_id = p.id
    ) support_stats on true
    where v_query = ''
       or p.id::text ilike '%' || v_query || '%'
       or coalesce(p.username, '') ilike '%' || v_query || '%'
       or coalesce(p.steam_name, '') ilike '%' || v_query || '%'
       or coalesce(p.steam_id, '') ilike '%' || v_query || '%'
       or (p.contact_email_verified_at is not null and coalesce(p.contact_email, '') ilike '%' || v_query || '%')
       or (coalesce(u.email, '') not ilike '%@steam.skinquestcs.com' and coalesce(u.email, '') ilike '%' || v_query || '%')
    order by p.created_at desc, p.id
    limit v_limit offset v_offset
  ) row_data;

  return jsonb_build_object('items', v_items, 'total', v_total);
end;
$$;

revoke all on function public.sq_admin_search_users(text,integer,integer) from public, anon, authenticated;
grant execute on function public.sq_admin_search_users(text,integer,integer) to authenticated;

-- Only manual rewards with no order history may be deleted.
create or replace function public.sq_owner_delete_manual_reward(p_reward_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_reward public.reward_items%rowtype;
begin
  if not public.is_owner() then raise exception 'Owner access required.'; end if;
  select * into v_reward from public.reward_items where id = p_reward_id for update;
  if not found then raise exception 'Reward not found.'; end if;
  if coalesce(v_reward.catalog_managed, false) then
    raise exception 'Steam-managed rewards cannot be deleted. Hide the listing instead.';
  end if;
  if coalesce(v_reward.quantity_reserved, 0) > 0 then
    raise exception 'This reward has reserved stock and cannot be deleted.';
  end if;
  if exists (select 1 from public.redemption_requests where reward_id = p_reward_id) then
    raise exception 'This reward has order history and cannot be deleted. Hide it instead.';
  end if;
  if exists (select 1 from public.favorite_rewards where reward_id = p_reward_id)
     or exists (select 1 from public.sq_reward_stock_subscriptions where reward_id = p_reward_id) then
    raise exception 'Customers have saved this reward. Hide it instead of deleting customer history.';
  end if;

  delete from public.reward_items where id = p_reward_id;
  -- The existing reward audit trigger records this deletion.
  return jsonb_build_object('ok', true, 'reward_id', p_reward_id, 'name', v_reward.name);
end;
$$;

revoke all on function public.sq_owner_delete_manual_reward(bigint) from public, anon, authenticated;
grant execute on function public.sq_owner_delete_manual_reward(bigint) to authenticated;

-- Preserve redemption history: only unused promo codes can be permanently deleted.
create or replace function public.sq_owner_delete_promo_code(p_promo_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_promo public.sq_promo_codes%rowtype;
begin
  if not public.is_owner() then raise exception 'Owner access required.'; end if;
  select * into v_promo from public.sq_promo_codes where id = p_promo_id for update;
  if not found then raise exception 'Promo code not found.'; end if;
  if coalesce(v_promo.redemptions_count, 0) > 0
     or exists (select 1 from public.sq_promo_redemptions where promo_code_id = p_promo_id) then
    raise exception 'Used promo codes cannot be deleted because their redemption history must be preserved.';
  end if;

  delete from public.sq_promo_codes where id = p_promo_id;
  insert into public.sq_admin_audit_log(actor_user_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'promo_delete', 'promo_code', p_promo_id::text,
    jsonb_build_object('code', v_promo.code, 'campaign', v_promo.campaign));
  return jsonb_build_object('ok', true, 'promo_id', p_promo_id, 'code', v_promo.code);
end;
$$;

revoke all on function public.sq_owner_delete_promo_code(bigint) from public, anon, authenticated;
grant execute on function public.sq_owner_delete_promo_code(bigint) to authenticated;

commit;

notify pgrst, 'reload schema';

-- v14.5.3 hybrid reward inventory, promo lifecycle, and history preservation.
begin;

-- Promo redemption snapshots let an owner remove a code without erasing who
-- redeemed it or how many coins were awarded.
alter table public.sq_promo_redemptions
  add column if not exists id bigint generated by default as identity;
alter table public.sq_promo_redemptions
  add column if not exists code_snapshot text;
alter table public.sq_promo_redemptions
  add column if not exists campaign_snapshot text;

update public.sq_promo_redemptions pr
set code_snapshot = coalesce(pr.code_snapshot, pc.code),
    campaign_snapshot = coalesce(pr.campaign_snapshot, pc.campaign)
from public.sq_promo_codes pc
where pc.id = pr.promo_code_id
  and (pr.code_snapshot is null or pr.campaign_snapshot is null);

alter table public.sq_promo_redemptions
  drop constraint if exists sq_promo_redemptions_pkey;
alter table public.sq_promo_redemptions
  drop constraint if exists sq_promo_redemptions_promo_code_id_fkey;
alter table public.sq_promo_redemptions
  alter column promo_code_id drop not null;
alter table public.sq_promo_redemptions
  add constraint sq_promo_redemptions_pkey primary key (id);
alter table public.sq_promo_redemptions
  add constraint sq_promo_redemptions_promo_code_id_fkey
  foreign key (promo_code_id) references public.sq_promo_codes(id) on delete set null;
create unique index if not exists sq_promo_redemptions_live_user_idx
  on public.sq_promo_redemptions(promo_code_id, user_id)
  where promo_code_id is not null;
create index if not exists sq_promo_redemptions_code_snapshot_idx
  on public.sq_promo_redemptions(upper(code_snapshot), user_id)
  where code_snapshot is not null;

create or replace function public.sq_snapshot_promo_redemption()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.promo_code_id is not null then
    select coalesce(new.code_snapshot, pc.code),
           coalesce(new.campaign_snapshot, pc.campaign)
    into new.code_snapshot, new.campaign_snapshot
    from public.sq_promo_codes pc
    where pc.id = new.promo_code_id;
  end if;
  return new;
end;
$$;

revoke all on function public.sq_snapshot_promo_redemption() from public, anon, authenticated;
drop trigger if exists sq_promo_redemption_snapshot on public.sq_promo_redemptions;
create trigger sq_promo_redemption_snapshot
before insert on public.sq_promo_redemptions
for each row execute function public.sq_snapshot_promo_redemption();

-- fulfillment_mode now describes whether an item can still be ordered after
create or replace function public.sq_validate_reward_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.quantity_total,0)<0 or coalesce(new.quantity_reserved,0)<0 then
    raise exception 'Stock cannot be negative.';
  end if;
  if coalesce(new.quantity_reserved,0)>coalesce(new.quantity_total,0) then
    raise exception 'Reserved stock cannot be higher than total stock.';
  end if;
  -- Changing the fallback does not change existing order fulfilment snapshots.
  return new;
end;
$$;

create or replace function public.sq_notify_restock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(old.quantity_total,0)-coalesce(old.quantity_reserved,0)<=0
     and coalesce(new.quantity_total,0)-coalesce(new.quantity_reserved,0)>0
     and coalesce(new.active,false) then
    insert into public.sq_notifications(user_id,notification_type,title,body,href,metadata)
    select s.user_id,'stock','Goal reward is back',
      coalesce(new.name,'A reward')||' is back in stock.',
      '/rewards?reward='||new.id,jsonb_build_object('reward_id',new.id)
    from public.sq_reward_stock_subscriptions s where s.reward_id=new.id;
    delete from public.sq_reward_stock_subscriptions where reward_id=new.id;
  end if;
  return new;
end;
$$;

-- fulfillment_mode now describes whether an item can still be ordered after
-- prepared stock reaches zero. Available stock is always used first.
create or replace function public.sq_reward_effective_fulfillment(
  p_fulfillment_mode text,
  p_quantity_total integer,
  p_quantity_reserved integer
)
returns text
language sql
immutable
as $$
  select case
    when greatest(0, coalesce(p_quantity_total, 0) - coalesce(p_quantity_reserved, 0)) > 0 then 'stocked'
    when p_fulfillment_mode = 'orderable' then 'orderable'
    else 'stocked'
  end;
$$;

revoke all on function public.sq_reward_effective_fulfillment(text,integer,integer) from public;
grant execute on function public.sq_reward_effective_fulfillment(text,integer,integer) to anon, authenticated, service_role;

create or replace function public.redeem_reward(p_reward_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_reward public.reward_items%rowtype;
  v_cost integer;
  v_available integer;
  v_request_id bigint;
  v_order_number text;
  v_user_redemptions integer;
  v_auth_email text;
  v_partner text;
  v_mode text;
  v_status text;
  v_estimated_ready_at timestamptz;
begin
  if v_user_id is null then raise exception 'You must be logged in.'; end if;
  perform public.ensure_skinquest_profile();
  select * into v_profile from public.profiles where id = v_user_id for update;
  if coalesce(v_profile.account_status, 'active') <> 'active' then raise exception 'Account is not active.'; end if;

  select lower(coalesce(email, '')) into v_auth_email from auth.users where id = v_user_id;
  if (v_auth_email = '' or v_auth_email like '%@steam.skinquestcs.com') and
     (nullif(trim(coalesce(v_profile.contact_email, '')), '') is null or v_profile.contact_email_verified_at is null) then
    raise exception 'Verified contact email required.';
  end if;
  if nullif(trim(coalesce(v_profile.steam_trade_url, '')), '') is null then raise exception 'Steam trade URL is required.'; end if;
  if v_profile.steam_trade_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?' or
     v_profile.steam_trade_url !~ '(^|[?&])partner=[0-9]+(&|$)' or
     v_profile.steam_trade_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)' then
    raise exception 'Steam trade URL is invalid.';
  end if;
  if v_profile.steam_id ~ '^[0-9]+$' then
    v_partner := substring(v_profile.steam_trade_url from '[?&]partner=([0-9]+)');
    if v_partner is null or v_partner::numeric <> (v_profile.steam_id::numeric - 76561197960265728::numeric) then
      raise exception 'Steam trade URL belongs to a different connected Steam account.';
    end if;
  end if;

  select * into v_reward from public.reward_items where id = p_reward_id and active = true for update;
  if not found then raise exception 'Reward not found.'; end if;
  v_cost := coalesce(nullif(v_reward.points_coins, 0), v_reward.points_cost, 0);
  if v_cost <= 0 then raise exception 'Reward price is invalid.'; end if;

  v_available := greatest(0, coalesce(v_reward.quantity_total, 0) - coalesce(v_reward.quantity_reserved, 0));
  v_mode := public.sq_reward_effective_fulfillment(
    v_reward.fulfillment_mode, v_reward.quantity_total, v_reward.quantity_reserved
  );
  if v_mode = 'stocked' then
    if v_available <= 0 then raise exception 'Reward is out of stock.'; end if;
    v_status := 'ready_to_trade';
    v_estimated_ready_at := now() + interval '2 days';
  else
    v_status := 'ordered';
    v_estimated_ready_at := now() + make_interval(days => greatest(7, least(coalesce(v_reward.order_eta_days, 8), 30)));
  end if;

  if v_reward.max_per_user is not null then
    select count(*) into v_user_redemptions
    from public.redemption_requests
    where user_id = v_user_id and reward_id = v_reward.id
      and status not in ('rejected', 'refunded', 'cancelled');
    if v_user_redemptions >= v_reward.max_per_user then
      raise exception 'You have reached the redemption limit for this reward.';
    end if;
  end if;
  if coalesce(v_profile.points_balance, 0) < v_cost then raise exception 'Not enough coins.'; end if;

  update public.profiles
  set points_balance = points_balance - v_cost, updated_at = now()
  where id = v_user_id;

  if v_mode = 'stocked' then
    update public.reward_items
    set quantity_reserved = coalesce(quantity_reserved, 0) + 1, updated_at = now()
    where id = v_reward.id;
  end if;

  insert into public.redemption_requests (
    user_id, reward_id, reward_name, points_coins, points_cost, steam_trade_url,
    status, fulfillment_mode, estimated_ready_at, ready_at
  ) values (
    v_user_id, v_reward.id, v_reward.name, v_cost, v_cost, v_profile.steam_trade_url,
    v_status, v_mode, v_estimated_ready_at,
    case when v_status = 'ready_to_trade' then now() else null end
  ) returning id, order_number into v_request_id, v_order_number;

  insert into public.coin_adjustments(user_id, amount, reason, source_type, source_id, metadata)
  values(
    v_user_id, -v_cost,
    case when v_mode = 'orderable' then 'Reward order / ' else 'Redeem hold / ' end || v_reward.name,
    case when v_mode = 'orderable' then 'reward_order' else 'redemption_hold' end,
    v_request_id::text,
    jsonb_build_object('reward_id',v_reward.id,'reward_name',v_reward.name,'fulfillment_mode',v_mode,'status',v_status)
  );

  return jsonb_build_object(
    'ok',true,'request_id',v_request_id,'order_number',v_order_number,
    'fulfillment_mode',v_mode,'status',v_status,'estimated_ready_at',v_estimated_ready_at
  );
end;
$$;

revoke all on function public.redeem_reward(bigint) from public, anon;
grant execute on function public.redeem_reward(bigint) to authenticated;

create or replace function public.sq_search_rewards(
  p_query text default null,
  p_min_coins integer default null,
  p_max_coins integer default null,
  p_availability text default 'all',
  p_balance integer default 0,
  p_sort text default 'price-desc',
  p_show_out_of_stock boolean default true,
  p_limit integer default 48,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := left(lower(trim(coalesce(p_query, ''))), 120);
  v_availability text := lower(coalesce(p_availability, 'all'));
  v_sort text := lower(coalesce(p_sort, 'price-desc'));
  v_limit integer := greatest(1, least(coalesce(p_limit, 48), 60));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  if v_availability not in ('all','affordable','in-stock','orderable') then v_availability := 'all'; end if;
  if v_sort not in ('price-asc','price-desc','featured','stock-desc','name-asc') then v_sort := 'price-desc'; end if;

  return (
    with filtered as (
      select r.*,
        greatest(0, coalesce(r.quantity_total,0) - coalesce(r.quantity_reserved,0)) as sq_available_stock,
        public.sq_reward_effective_fulfillment(r.fulfillment_mode,r.quantity_total,r.quantity_reserved) as sq_current_fulfillment,
        case when greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) <= 0
                   and r.fulfillment_mode <> 'orderable' then 1 else 0 end as sq_out_of_stock
      from public.reward_items r
      where r.active = true
        and (
          v_query = '' or lower(coalesce(r.name,'')) like '%' || v_query || '%'
          or lower(coalesce(r.market_name,'')) like '%' || v_query || '%'
          or lower(coalesce(r.description,'')) like '%' || v_query || '%'
          or lower(coalesce(r.rarity,'')) like '%' || v_query || '%'
          or lower(coalesce(r.condition,'')) like '%' || v_query || '%'
        )
        and (p_min_coins is null or r.points_coins >= greatest(0,p_min_coins))
        and (p_max_coins is null or r.points_coins <= greatest(0,p_max_coins))
        and (
          coalesce(p_show_out_of_stock,true)
          or r.fulfillment_mode = 'orderable'
          or greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) > 0
        )
        and (
          v_availability = 'all'
          or (v_availability = 'affordable'
              and r.points_coins <= greatest(0,coalesce(p_balance,0))
              and (r.fulfillment_mode = 'orderable'
                   or greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) > 0))
          or (v_availability = 'in-stock'
              and greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) > 0)
          or (v_availability = 'orderable'
              and r.fulfillment_mode = 'orderable'
              and greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) <= 0)
        )
    ), ordered as (
      select f.*, row_number() over (order by
        f.sq_out_of_stock asc,
        case when v_sort = 'price-asc' then f.points_coins end asc nulls last,
        case when v_sort = 'price-desc' then f.points_coins end desc nulls last,
        case when v_sort = 'stock-desc' then f.sq_available_stock end desc nulls last,
        case when v_sort = 'featured' then f.sort_order end asc nulls last,
        case when v_sort = 'name-asc' then lower(f.name) end asc nulls last,
        lower(f.name) asc, f.id asc
      ) as sq_row_number
      from filtered f
    ), page as (
      select * from ordered
      where sq_row_number > v_offset and sq_row_number <= v_offset + v_limit
    )
    select jsonb_build_object(
      'items', coalesce((
        select jsonb_agg(
          (to_jsonb(p)-'sq_row_number'-'sq_available_stock'-'sq_out_of_stock'-'sq_current_fulfillment')
          || jsonb_build_object(
            'available_stock',p.sq_available_stock,
            'current_fulfillment',p.sq_current_fulfillment,
            'price_is_current',p.pricing_mode <> 'steam' or (
              coalesce(p.steam_price_minor,0) > 0
              and p.steam_price_valid_until is not null
              and p.steam_price_valid_until > now()
            )
          ) order by p.sq_row_number
        ) from page p
      ), '[]'::jsonb),
      'total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset
    )
  );
end;
$$;

revoke all on function public.sq_search_rewards(text,integer,integer,text,integer,text,boolean,integer,integer) from public;
grant execute on function public.sq_search_rewards(text,integer,integer,text,integer,text,boolean,integer,integer) to anon, authenticated;

drop function if exists public.sq_admin_search_reward_items(text,text,integer,integer);
create function public.sq_admin_search_reward_items(
  p_query text default null,
  p_filter text default 'all',
  p_sort text default 'stock-first',
  p_limit integer default 75,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := left(lower(trim(coalesce(p_query,''))),120);
  v_filter text := lower(coalesce(p_filter,'all'));
  v_sort text := lower(coalesce(p_sort,'stock-first'));
  v_limit integer := greatest(1,least(coalesce(p_limit,75),150));
  v_offset integer := greatest(0,coalesce(p_offset,0));
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  if v_filter not in ('all','stocked','orderable','steam','stale','inactive') then v_filter := 'all'; end if;
  if v_sort not in ('stock-first','order-first','name-asc','price-asc','price-desc') then v_sort := 'stock-first'; end if;

  return (
    with filtered as (
      select r.*,
        greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) as sq_available_stock,
        public.sq_reward_effective_fulfillment(r.fulfillment_mode,r.quantity_total,r.quantity_reserved) as sq_current_fulfillment
      from public.reward_items r
      where (
        v_query = '' or lower(coalesce(r.name,'')) like '%' || v_query || '%'
        or lower(coalesce(r.market_name,'')) like '%' || v_query || '%'
        or lower(coalesce(r.rarity,'')) like '%' || v_query || '%'
        or lower(coalesce(r.condition,'')) like '%' || v_query || '%'
      )
      and (
        v_filter = 'all'
        or (v_filter = 'stocked' and greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) > 0)
        or (v_filter = 'orderable' and r.fulfillment_mode = 'orderable'
            and greatest(0,coalesce(r.quantity_total,0)-coalesce(r.quantity_reserved,0)) <= 0)
        or (v_filter = 'steam' and r.pricing_mode = 'steam')
        or (v_filter = 'stale' and r.pricing_mode = 'steam' and (
          coalesce(r.steam_price_minor,0) <= 0 or r.steam_price_valid_until is null or r.steam_price_valid_until <= now()
        ))
        or (v_filter = 'inactive' and r.active = false)
      )
    ), ordered as (
      select f.*, row_number() over (order by
        f.active desc,
        case when v_sort = 'stock-first' then case when f.sq_available_stock > 0 then 0 else 1 end end asc nulls last,
        case when v_sort = 'order-first' then case when f.sq_current_fulfillment = 'orderable' then 0 else 1 end end asc nulls last,
        case when v_sort = 'name-asc' then lower(f.name) end asc nulls last,
        case when v_sort = 'price-asc' then f.points_coins end asc nulls last,
        case when v_sort = 'price-desc' then f.points_coins end desc nulls last,
        f.sort_order asc, lower(f.name) asc, f.id asc
      ) as sq_row_number
      from filtered f
    ), page as (
      select * from ordered
      where sq_row_number > v_offset and sq_row_number <= v_offset + v_limit
    )
    select jsonb_build_object(
      'items',coalesce((
        select jsonb_agg(
          (to_jsonb(p)-'sq_row_number'-'sq_available_stock'-'sq_current_fulfillment')
          || jsonb_build_object('available_stock',p.sq_available_stock,'current_fulfillment',p.sq_current_fulfillment)
          order by p.sq_row_number
        ) from page p
      ),'[]'::jsonb),
      'total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset
    )
  );
end;
$$;

revoke all on function public.sq_admin_search_reward_items(text,text,text,integer,integer) from public, anon, authenticated;
grant execute on function public.sq_admin_search_reward_items(text,text,text,integer,integer) to authenticated;

create or replace function public.sq_admin_reward_pricing_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  return jsonb_build_object(
    'settings',coalesce((select to_jsonb(s) from public.sq_reward_pricing_settings s where id=1),'{}'::jsonb),
    'sync',coalesce((select to_jsonb(c) from public.sq_steam_catalog_sync_state c where id=1),'{}'::jsonb),
    'stats',jsonb_build_object(
      'active_listings',(select count(*) from public.reward_items where active=true),
      'orderable_listings',(select count(*) from public.reward_items where active=true and fulfillment_mode='orderable'
        and greatest(0,coalesce(quantity_total,0)-coalesce(quantity_reserved,0))<=0),
      'prepared_units',(select coalesce(sum(greatest(0,quantity_total-quantity_reserved)),0) from public.reward_items),
      'reserved_units',(select coalesce(sum(greatest(0,quantity_reserved)),0) from public.reward_items),
      'steam_linked',(select count(*) from public.reward_items where pricing_mode='steam'),
      'stale_prices',(select count(*) from public.reward_items where active=true and pricing_mode='steam' and (
        coalesce(steam_price_minor,0)<=0 or steam_price_valid_until is null or steam_price_valid_until<=now()
      )),
      'catalog_items',(select count(*) from public.reward_items where catalog_managed=true)
    )
  );
end;
$$;

revoke all on function public.sq_admin_reward_pricing_dashboard() from public, anon, authenticated;
grant execute on function public.sq_admin_reward_pricing_dashboard() to authenticated;

-- New custom rewards use an RPC so an exact existing Steam/name match cannot
-- silently create a duplicate listing.
create or replace function public.sq_owner_create_manual_reward(p_reward jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := left(trim(coalesce(p_reward->>'name','')),240);
  v_market_name text := nullif(left(trim(coalesce(p_reward->>'market_name','')),240),'');
  v_existing_id bigint;
  v_id bigint;
  v_points integer;
  v_total integer;
  v_reserved integer;
  v_eta integer;
  v_sort integer;
  v_max integer;
  v_fulfillment text;
begin
  if not public.is_owner() then raise exception 'Owner access required.'; end if;
  if v_name = '' then raise exception 'Reward name is required.'; end if;

  select r.id into v_existing_id
  from public.reward_items r
  where (v_market_name is not null and lower(coalesce(r.market_name,''))=lower(v_market_name))
     or lower(trim(r.name))=lower(v_name)
  order by case when v_market_name is not null and lower(coalesce(r.market_name,''))=lower(v_market_name) then 0 else 1 end, r.id
  limit 1;
  if v_existing_id is not null then
    return jsonb_build_object('ok',true,'existing',true,'id',v_existing_id,'name',
      (select name from public.reward_items where id=v_existing_id));
  end if;

  begin
    v_points := (p_reward->>'points_coins')::integer;
    v_total := coalesce((p_reward->>'quantity_total')::integer,0);
    v_reserved := coalesce((p_reward->>'quantity_reserved')::integer,0);
    v_eta := coalesce((p_reward->>'order_eta_days')::integer,8);
    v_sort := coalesce((p_reward->>'sort_order')::integer,0);
    v_max := nullif(p_reward->>'max_per_user','')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Reward numbers are invalid.';
  end;
  v_fulfillment := case when p_reward->>'fulfillment_mode'='orderable' then 'orderable' else 'stocked' end;
  if v_points < 1 then raise exception 'Coin price must be at least 1.'; end if;
  if v_total < 0 or v_reserved < 0 or v_reserved > v_total then raise exception 'Reserved stock must be between 0 and total stock.'; end if;
  if v_eta < 7 or v_eta > 30 then raise exception 'Order ETA must be between 7 and 30 days.'; end if;
  if v_max is not null and v_max < 1 then raise exception 'User limit must be above 0.'; end if;

  insert into public.reward_items(
    name,market_name,description,image_url,rarity,condition,
    points_coins,points_cost,quantity_total,quantity_reserved,
    active,sort_order,max_per_user,fulfillment_mode,order_eta_days,
    pricing_mode,manual_price_override,catalog_managed
  ) values(
    v_name,v_market_name,nullif(left(trim(coalesce(p_reward->>'description','')),500),''),
    nullif(left(trim(coalesce(p_reward->>'image_url','')),500),''),
    nullif(left(lower(trim(coalesce(p_reward->>'rarity',''))),40),''),
    nullif(left(trim(coalesce(p_reward->>'condition','')),40),''),
    v_points,v_points,v_total,v_reserved,
    coalesce((p_reward->>'active')::boolean,true),v_sort,v_max,v_fulfillment,v_eta,
    'manual',true,false
  ) returning id into v_id;
  return jsonb_build_object('ok',true,'existing',false,'id',v_id,'name',v_name);
end;
$$;

revoke all on function public.sq_owner_create_manual_reward(jsonb) from public, anon, authenticated;
grant execute on function public.sq_owner_create_manual_reward(jsonb) to authenticated;

create or replace function public.sq_owner_delete_manual_reward(p_reward_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_reward public.reward_items%rowtype;
begin
  if not public.is_owner() then raise exception 'Owner access required.'; end if;
  select * into v_reward from public.reward_items where id=p_reward_id for update;
  if not found then raise exception 'Reward not found.'; end if;
  if coalesce(v_reward.catalog_managed,false) then
    raise exception 'Steam-managed rewards return on the next sync. Hide them instead.';
  end if;
  if coalesce(v_reward.quantity_reserved,0)>0 or exists(
    select 1 from public.redemption_requests
    where reward_id=p_reward_id
      and status not in ('completed','rejected','refunded','cancelled')
  ) then
    raise exception 'Finish or cancel this reward''s open orders before deleting it.';
  end if;

  delete from public.reward_items where id=p_reward_id;
  -- Existing order rows keep reward_name and coin snapshots; the FK sets
  -- reward_id to NULL and the UI labels those rows as deleted items.
  return jsonb_build_object('ok',true,'reward_id',p_reward_id,'name',v_reward.name);
end;
$$;

revoke all on function public.sq_owner_delete_manual_reward(bigint) from public, anon, authenticated;
grant execute on function public.sq_owner_delete_manual_reward(bigint) to authenticated;

create or replace function public.sq_owner_set_promo_active(p_promo_id bigint,p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_promo public.sq_promo_codes%rowtype;
begin
  if not public.is_owner() then raise exception 'Owner access required.'; end if;
  update public.sq_promo_codes
  set active=coalesce(p_active,false)
  where id=p_promo_id
  returning * into v_promo;
  if not found then raise exception 'Promo code not found.'; end if;
  insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
  values(auth.uid(),'promo_status_update','promo_code',p_promo_id::text,
    jsonb_build_object('code',v_promo.code,'active',v_promo.active));
  return jsonb_build_object('ok',true,'id',v_promo.id,'code',v_promo.code,'active',v_promo.active);
end;
$$;

revoke all on function public.sq_owner_set_promo_active(bigint,boolean) from public, anon, authenticated;
grant execute on function public.sq_owner_set_promo_active(bigint,boolean) to authenticated;

create or replace function public.sq_owner_delete_promo_code(p_promo_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_promo public.sq_promo_codes%rowtype;
begin
  if not public.is_owner() then raise exception 'Owner access required.'; end if;
  select * into v_promo from public.sq_promo_codes where id=p_promo_id for update;
  if not found then raise exception 'Promo code not found.'; end if;
  delete from public.sq_promo_codes where id=p_promo_id;
  insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
  values(auth.uid(),'promo_delete','promo_code',p_promo_id::text,
    jsonb_build_object('code',v_promo.code,'campaign',v_promo.campaign,'redemptions',v_promo.redemptions_count));
  return jsonb_build_object('ok',true,'promo_id',p_promo_id,'code',v_promo.code,
    'preserved_redemptions',coalesce(v_promo.redemptions_count,0));
end;
$$;

revoke all on function public.sq_owner_delete_promo_code(bigint) from public, anon, authenticated;
grant execute on function public.sq_owner_delete_promo_code(bigint) to authenticated;

create or replace function public.sq_admin_search_promo_codes(
  p_query text default null,
  p_state text default 'all',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_query text := left(lower(trim(coalesce(p_query,''))),120);
  v_state text := lower(coalesce(p_state,'all'));
  v_limit integer := greatest(1,least(coalesce(p_limit,100),200));
  v_offset integer := greatest(0,coalesce(p_offset,0));
begin
  if not public.is_admin() then raise exception 'Admin access required.'; end if;
  if v_state not in ('all','active','inactive') then v_state := 'all'; end if;
  return (
    with filtered as (
      select p.*
      from public.sq_promo_codes p
      where (v_query='' or lower(p.code) like '%'||v_query||'%'
        or lower(coalesce(p.campaign,'')) like '%'||v_query||'%')
        and (
          v_state='all'
          or (v_state='active' and p.active=true
            and (p.starts_at is null or p.starts_at<=now())
            and (p.ends_at is null or p.ends_at>now())
            and (p.max_redemptions is null or p.redemptions_count<p.max_redemptions))
          or (v_state='inactive' and not (
            p.active=true
            and (p.starts_at is null or p.starts_at<=now())
            and (p.ends_at is null or p.ends_at>now())
            and (p.max_redemptions is null or p.redemptions_count<p.max_redemptions)
          ))
        )
    ), page as (
      select * from filtered order by created_at desc,id desc limit v_limit offset v_offset
    )
    select jsonb_build_object(
      'items',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc,p.id desc) from page p),'[]'::jsonb),
      'total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset
    )
  );
end;
$$;

revoke all on function public.sq_admin_search_promo_codes(text,text,integer,integer) from public, anon, authenticated;
grant execute on function public.sq_admin_search_promo_codes(text,text,integer,integer) to authenticated;

create or replace function public.sq_redeem_promo_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(btrim(coalesce(p_code,'')));
  v_promo public.sq_promo_codes%rowtype;
begin
  if v_user is null then raise exception 'Sign in required.'; end if;
  if length(v_code)<3 then raise exception 'Enter a valid code.'; end if;
  select * into v_promo from public.sq_promo_codes where upper(code)=v_code for update;
  if not found then raise exception 'That code does not exist.'; end if;
  if not v_promo.active then raise exception 'That code is inactive.'; end if;
  if v_promo.starts_at is not null and now()<v_promo.starts_at then raise exception 'That code is not active yet.'; end if;
  if v_promo.ends_at is not null and now()>=v_promo.ends_at then raise exception 'That code has expired.'; end if;
  if v_promo.max_redemptions is not null and v_promo.redemptions_count>=v_promo.max_redemptions then
    raise exception 'That code has reached its redemption limit.';
  end if;
  if exists(
    select 1 from public.sq_promo_redemptions
    where user_id=v_user and (
      promo_code_id=v_promo.id or upper(coalesce(code_snapshot,''))=v_code
    )
  ) then raise exception 'You have already redeemed that code.'; end if;

  perform 1 from public.profiles where id=v_user for update;
  if not found then raise exception 'Profile not found.'; end if;
  insert into public.sq_promo_redemptions(
    promo_code_id,user_id,coins_awarded,code_snapshot,campaign_snapshot
  ) values(v_promo.id,v_user,v_promo.coin_amount,v_promo.code,v_promo.campaign);
  update public.sq_promo_codes set redemptions_count=redemptions_count+1 where id=v_promo.id;
  update public.profiles set points_balance=coalesce(points_balance,0)+v_promo.coin_amount where id=v_user;
  insert into public.coin_adjustments(user_id,amount,reason)
  values(v_user,v_promo.coin_amount,'Promo code: '||v_promo.code);
  insert into public.sq_product_events(user_id,event_name,page_path,properties)
  values(v_user,'promo_redeemed',null,jsonb_build_object('campaign',v_promo.campaign,'coins',v_promo.coin_amount));
  return jsonb_build_object('ok',true,'coins_awarded',v_promo.coin_amount,'campaign',v_promo.campaign);
end;
$$;

revoke all on function public.sq_redeem_promo_code(text) from public;
grant execute on function public.sq_redeem_promo_code(text) to authenticated;

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
  v_code text := upper(regexp_replace(btrim(coalesce(p_code,'')),'[^A-Za-z0-9_-]+','','g'));
  v_id bigint;
begin
  if not public.sq_is_admin() then raise exception 'Admin access required.'; end if;
  if length(v_code)<3 then raise exception 'Code must contain at least 3 valid characters.'; end if;
  if p_coin_amount<=0 or p_coin_amount>100000 then raise exception 'Coin amount is outside the allowed range.'; end if;
  if p_max_redemptions is not null and p_max_redemptions<=0 then raise exception 'Max redemptions must be positive.'; end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at<=p_starts_at then raise exception 'End must be after start.'; end if;
  if exists(select 1 from public.sq_promo_redemptions where upper(coalesce(code_snapshot,''))=v_code) then
    raise exception 'That code was used before and cannot be recreated after deletion.';
  end if;
  insert into public.sq_promo_codes(code,campaign,coin_amount,max_redemptions,starts_at,ends_at,created_by)
  values(v_code,nullif(btrim(p_campaign),''),p_coin_amount,p_max_redemptions,p_starts_at,p_ends_at,auth.uid())
  returning id into v_id;
  insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
  values(auth.uid(),'promo_create','promo_code',v_id::text,
    jsonb_build_object('code',v_code,'coins',p_coin_amount,'max',p_max_redemptions,'campaign',p_campaign));
  return jsonb_build_object('ok',true,'id',v_id,'code',v_code);
end;
$$;

revoke all on function public.sq_admin_create_promo_code(text,integer,text,integer,timestamptz,timestamptz) from public;
grant execute on function public.sq_admin_create_promo_code(text,integer,text,integer,timestamptz,timestamptz) to authenticated;

commit;
notify pgrst, 'reload schema';

-- v14.5.4 legacy reward-link repair and user filters.
-- SkinQuest v14.5.3 -> v14.5.4. Back up first; run only this upgrade.
begin;
lock table public.reward_items, public.redemption_requests in share row exclusive mode;

-- Normalize the legacy link without deleting orders or changing coin snapshots.
do $$
declare c record; v_conflict boolean;
begin
  if exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='redemption_requests' and column_name='reward_item_id') then
    execute 'select exists(select 1 from public.redemption_requests where reward_id is not null
      and reward_item_id is not null and reward_id<>reward_item_id)' into v_conflict;
    if v_conflict then raise exception 'Conflicting legacy reward links. No changes applied; inspect the affected orders first.'; end if;
    execute 'update public.redemption_requests set reward_id=reward_item_id
      where reward_id is null and reward_item_id is not null';
  end if;
  for c in
    select con.conname, a.attname
    from pg_constraint con
    join pg_attribute a on a.attrelid=con.conrelid and a.attnum=con.conkey[1]
    join pg_attribute b on b.attrelid=con.confrelid and b.attnum=con.confkey[1]
    where con.contype='f' and con.conrelid='public.redemption_requests'::regclass
      and con.confrelid='public.reward_items'::regclass
      and cardinality(con.conkey)=1 and cardinality(con.confkey)=1
      and a.attname in ('reward_id','reward_item_id') and b.attname='id'
  loop
    execute format('alter table public.redemption_requests alter column %I drop not null',c.attname);
    execute format('alter table public.redemption_requests drop constraint %I',c.conname);
    execute format('alter table public.redemption_requests add constraint %I foreign key (%I) references public.reward_items(id) on delete set null',c.conname,c.attname);
  end loop;
end;
$$;

-- A separate RPC preserves compatibility with existing global user search.
create or replace function public.sq_admin_filter_users(
 p_query text default null,p_role text default 'all',p_login text default 'all',
 p_sort text default 'newest',p_limit integer default 75,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare
 v_query text:=left(trim(coalesce(p_query,'')),120);
 v_role text:=coalesce(p_role,'all');
 v_login text:=coalesce(p_login,'all');
 v_sort text:=coalesce(p_sort,'newest');
 v_limit integer:=greatest(1,least(coalesce(p_limit,75),200));
 v_offset integer:=greatest(0,coalesce(p_offset,0));
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if v_role not in ('all','user','staff','admin','owner') then v_role:='all'; end if;
 if v_login not in ('all','steam','other') then v_login:='all'; end if;
 if v_sort not in ('newest','oldest','coins-desc','coins-asc','role','name') then v_sort:='newest'; end if;
 return (
 with base as (
 select p.id as user_id,
 case when coalesce(u.email,'') ilike '%@steam.skinquestcs.com' then null else u.email::text end as email,
 p.username,p.steam_name,p.steam_id,
 case when p.contact_email_verified_at is not null then p.contact_email else null end as contact_email,
 p.contact_email_verified_at,coalesce(p.points_balance,0) as points_balance,
 coalesce(p.account_status,'active') as account_status,p.created_at,
 coalesce(au.role,'user') as role,
 (coalesce(u.email,'') ilike '%@steam.skinquestcs.com'
  or coalesce(u.raw_app_meta_data->>'provider','')='steam'
  or coalesce(u.raw_app_meta_data->'providers','[]'::jsonb) ? 'steam'
  or exists(select 1 from auth.identities i where i.user_id=p.id and i.provider='steam')) as steam_login
 from public.profiles p left join auth.users u on u.id=p.id
 left join public.admin_users au on au.user_id=p.id
 where v_query='' or p.id::text ilike '%'||v_query||'%'
 or coalesce(p.username,'') ilike '%'||v_query||'%'
 or coalesce(p.steam_name,'') ilike '%'||v_query||'%'
 or coalesce(p.steam_id,'') ilike '%'||v_query||'%'
 or (p.contact_email_verified_at is not null and coalesce(p.contact_email,'') ilike '%'||v_query||'%')
 or (coalesce(u.email,'') not ilike '%@steam.skinquestcs.com' and coalesce(u.email,'') ilike '%'||v_query||'%')
 ), filtered as (
 select * from base where (v_role='all' or role=v_role or (v_role='staff' and role in ('admin','owner')))
 and (v_login='all' or (v_login='steam' and steam_login) or (v_login='other' and not steam_login))
 ), ordered as (
 select f.*,row_number() over(order by
 case when v_sort='newest' then created_at end desc nulls last,
 case when v_sort='oldest' then created_at end asc nulls last,
 case when v_sort='coins-desc' then points_balance end desc,
 case when v_sort='coins-asc' then points_balance end asc,
 case when v_sort='role' then case role when 'owner' then 0 when 'admin' then 1 else 2 end end asc,
 case when v_sort='name' then lower(coalesce(nullif(steam_name,''),nullif(username,''),contact_email,email,user_id::text)) end asc,
 user_id asc) as row_num from filtered f
 ), page as (
 select * from ordered where row_num>v_offset and row_num<=v_offset+v_limit
 ), enriched as (
 select p.*,
 (select count(*) from public.redemption_requests r where r.user_id=p.user_id) as order_count,
 (select count(*) from public.redemption_requests r where r.user_id=p.user_id and r.status='completed') as completed_count,
 (select count(*) from public.support_requests s where s.user_id=p.user_id) as support_count
 from page p
 )
 select jsonb_build_object('total',(select count(*) from filtered),
 'items',coalesce((select jsonb_agg(to_jsonb(e)-'row_num' order by e.row_num) from enriched e),'[]'::jsonb))
 );
end;
$$;
revoke all on function public.sq_admin_filter_users(text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_filter_users(text,text,text,text,integer,integer) to authenticated;
commit;
notify pgrst,'reload schema';

-- v14.5.5 account dates and honest CPX activity metrics.
-- SkinQuest v14.5.4 -> v14.5.5. Back up first; run only this upgrade.
begin;
create index if not exists sq_cpx_open_analytics_idx
on public.sq_product_events(user_id) where event_name='cpx_wall_open_requested';
create index if not exists sq_cpx_completed_analytics_idx
on public.offerwall_events(user_id) where provider='cpx' and status='completed';

create or replace function public.sq_admin_users_activity(
 p_query text default null,p_role text default 'all',p_login text default 'all',
 p_sort text default 'newest',p_limit integer default 75,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare v_result jsonb; v_items jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 v_result:=public.sq_admin_filter_users(p_query,p_role,p_login,p_sort,p_limit,p_offset);
 select coalesce(jsonb_agg(
   e.item || jsonb_build_object(
    'account_created_at',u.created_at,
    'verified_cpx_rewards',(select count(*) from public.offerwall_events o
      where o.user_id=u.id and o.provider='cpx' and o.status='completed'),
    'cpx_opens',(select count(*) from public.sq_product_events p
      where p.user_id=u.id and p.event_name='cpx_wall_open_requested')
   ) order by e.ord),'[]'::jsonb)
 into v_items
 from jsonb_array_elements(v_result->'items') with ordinality as e(item,ord)
 left join auth.users u on u.id=(e.item->>'user_id')::uuid;
 return v_result || jsonb_build_object('items',v_items);
end;
$$;
revoke all on function public.sq_admin_users_activity(text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_users_activity(text,text,text,text,integer,integer) to authenticated;
commit;
notify pgrst,'reload schema';

-- v14.5.6 user workspace, presence and CPX evidence.
-- SkinQuest v14.5.5 -> v14.5.6. Back up first; run only this upgrade.
begin;
create table if not exists public.sq_user_presence(
 user_id uuid primary key references auth.users(id) on delete cascade,
 last_active_at timestamptz not null default now()
);
alter table public.sq_user_presence enable row level security;
revoke all on public.sq_user_presence from public,anon,authenticated;
grant select on public.sq_user_presence to authenticated;
drop policy if exists sq_presence_read on public.sq_user_presence;
create policy sq_presence_read on public.sq_user_presence for select
using(user_id=auth.uid() or public.is_admin());

create or replace function public.sq_touch_activity()
returns boolean language plpgsql security definer set search_path=public,auth as $$
begin
 if auth.uid() is null then return false; end if;
 insert into public.sq_user_presence(user_id,last_active_at) values(auth.uid(),now())
 on conflict(user_id) do update set last_active_at=excluded.last_active_at
 where public.sq_user_presence.last_active_at<now()-interval '1 minute';
 return true;
end;
$$;
revoke all on function public.sq_touch_activity() from public,anon,authenticated;
grant execute on function public.sq_touch_activity() to authenticated;

create index if not exists sq_daily_last_activity_idx on public.sq_daily_activity(user_id,last_seen_at desc);
create index if not exists sq_product_last_activity_idx on public.sq_product_events(user_id,created_at desc);
create or replace function public.sq_admin_last_active(p_user_id uuid)
returns timestamptz language plpgsql stable security definer set search_path=public,auth as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 return greatest(
 (select last_active_at from public.sq_user_presence where user_id=p_user_id),
 (select max(last_seen_at) from public.sq_daily_activity where user_id=p_user_id),
 (select max(created_at) from public.sq_product_events where user_id=p_user_id));
end;
$$;
revoke all on function public.sq_admin_last_active(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_last_active(uuid) to authenticated;

create or replace function public.sq_admin_cpx_activity(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_events bigint; v_ledger bigint; v_opens bigint; v_all bigint;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 select count(*),count(*) filter(where lower(status)='completed')
 into v_all,v_events from public.offerwall_events
 where user_id=p_user_id and lower(provider) in ('cpx','cpx-research','cpx_research');
 select count(*) into v_ledger from public.coin_adjustments
 where user_id=p_user_id and amount>0
 and (lower(coalesce(source_id,'')) like 'cpx:%'
 or (source_type='offerwall_credit' and lower(coalesce(metadata->>'provider','')) in ('cpx','cpx-research','cpx_research'))
 or coalesce(reason,'') ~* '^CPX([[:space:]:_-]|$)');
 select count(*) into v_opens from public.sq_product_events
 where user_id=p_user_id and event_name='cpx_wall_open_requested';
 return jsonb_build_object(
 'completed_reward_events',case when v_all>0 then v_events else null end,
 'postback_rows',v_all,'ledger_credit_rows',nullif(v_ledger,0),
 'logged_opens',nullif(v_opens,0),
 'note','Postbacks may include screen-out compensation. Ledger counts are CPX-labelled credits, not proof of full surveys. Opens are observed CPX launch clicks, not individual surveys inside the widget.');
end;
$$;
revoke all on function public.sq_admin_cpx_activity(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_cpx_activity(uuid) to authenticated;

create or replace function public.sq_admin_users_activity(
 p_query text default null,p_role text default 'all',p_login text default 'all',
 p_sort text default 'newest',p_limit integer default 75,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_result jsonb; v_items jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 v_result:=public.sq_admin_filter_users(p_query,p_role,p_login,p_sort,p_limit,p_offset);
 select coalesce(jsonb_agg(
 e.item || jsonb_build_object('account_created_at',u.created_at,
 'last_active_at',public.sq_admin_last_active(u.id)) order by e.ord),'[]'::jsonb)
 into v_items
 from jsonb_array_elements(v_result->'items') with ordinality as e(item,ord)
 left join auth.users u on u.id=(e.item->>'user_id')::uuid;
 return v_result || jsonb_build_object('items',v_items);
end;
$$;
revoke all on function public.sq_admin_users_activity(text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_users_activity(text,text,text,text,integer,integer) to authenticated;

create or replace function public.sq_admin_user_profile(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_result jsonb; v_user jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 v_result:=public.sq_admin_users_activity(p_user_id::text,'all','all','newest',200,0);
 select e.item into v_user from jsonb_array_elements(v_result->'items') as e(item)
 where e.item->>'user_id'=p_user_id::text;
 if v_user is null then raise exception 'User not found.'; end if;
 return jsonb_build_object('user',v_user,'cpx',public.sq_admin_cpx_activity(p_user_id));
end;
$$;
revoke all on function public.sq_admin_user_profile(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_user_profile(uuid) to authenticated;

create or replace function public.sq_admin_user_records(
 p_user_id uuid,p_section text default 'orders',p_limit integer default 25,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_table text; v_columns text; v_date text; v_total bigint; v_items jsonb;
 v_limit integer:=greatest(1,least(coalesce(p_limit,25),100));
 v_offset integer:=greatest(0,coalesce(p_offset,0));
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 case p_section
 when 'orders' then v_table:='redemption_requests'; v_date:='created_at'; v_columns:='id,order_number,reward_id,reward_name,points_coins,points_cost,status,created_at';
 when 'support' then v_table:='support_requests'; v_date:='created_at'; v_columns:='id,ticket_number,topic,status,created_at';
 when 'coins' then v_table:='coin_adjustments'; v_date:='created_at'; v_columns:='id,amount,reason,source_type,source_id,created_at';
 when 'promos' then v_table:='sq_promo_redemptions'; v_date:='redeemed_at'; v_columns:='id,promo_code_id,code_snapshot,campaign_snapshot,coins_awarded,redeemed_at';
 when 'surveys' then v_table:='offerwall_events'; v_date:='created_at'; v_columns:='id,provider,provider_event_id,amount,status,created_at,processed_at';
 else raise exception 'Invalid user-history section.';
 end case;
 execute format('select count(*) from public.%I where user_id=$1',v_table)
 into v_total using p_user_id;
 execute format('select coalesce(jsonb_agg(to_jsonb(r) order by r.%I desc,r.id desc),''[]''::jsonb)
 from (select %s from public.%I where user_id=$1 order by %I desc,id desc limit $2 offset $3) r',
 v_date,v_columns,v_table,v_date)
 into v_items using p_user_id,v_limit,v_offset;
 return jsonb_build_object('items',v_items,'total',v_total,'offset',v_offset,'limit',v_limit);
end;
$$;
revoke all on function public.sq_admin_user_records(uuid,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_user_records(uuid,text,integer,integer) to authenticated;
commit;
notify pgrst,'reload schema';
