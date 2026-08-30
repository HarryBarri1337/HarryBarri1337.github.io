-- SkinQuest upgrade for EXISTING projects -> v14.1.3
-- Run this ONCE in Supabase SQL Editor when upgrading from v14.1.2.
-- Adds verified contact emails for Steam sign-ins and stronger trade-link ownership checks.

alter table public.profiles add column if not exists contact_email text;
alter table public.profiles add column if not exists contact_email_verified_at timestamptz;

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

alter table public.contact_email_verifications enable row level security;
revoke all on public.contact_email_verifications from anon, authenticated;

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

-- Rebuild admin notification views so verified Steam contact emails are used instead of synthetic auth addresses.
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
select * from public.admin_notification_subscribers
where reward_updates = true and email is not null;

create or replace view public.admin_notification_offer_issue_emails as
select * from public.admin_notification_subscribers
where offer_issues = true and email is not null;

create or replace view public.admin_notification_product_update_emails as
select * from public.admin_notification_subscribers
where product_updates = true and email is not null;

grant select on public.admin_notification_subscribers to authenticated;
grant select on public.admin_notification_reward_update_emails to authenticated;
grant select on public.admin_notification_offer_issue_emails to authenticated;
grant select on public.admin_notification_product_update_emails to authenticated;

grant execute on function public.save_skinquest_trade_url(text) to authenticated;
grant execute on function public.redeem_reward(bigint) to authenticated;
