-- SkinQuest existing-project repair v12.2.10
-- Run this once on the CURRENT Supabase project.
-- This migration intentionally backtracks redemption to the last known-working
-- v12.2.4 implementation and changes only the Trade URL save path around it.

begin;

alter table public.profiles add column if not exists steam_trade_url text;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

-- Restore the stable Trade URL RPC with flexible parameter ordering.
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


-- Remove only conflicting redeem overloads, then restore the known-working bigint RPC.
drop function if exists public.redeem_reward(integer);
drop function if exists public.redeem_reward(numeric);
drop function if exists public.redeem_reward(text);

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


-- The frontend normally uses the security-definer RPC. This restricted policy
-- is only a fallback for the authenticated user's own steam_trade_url column.
alter table public.profiles enable row level security;
drop policy if exists profiles_update_own_trade_url on public.profiles;
create policy profiles_update_own_trade_url on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

grant select on public.profiles to authenticated;
grant update (steam_trade_url) on public.profiles to authenticated;

revoke all on function public.save_skinquest_trade_url(text) from public;
grant execute on function public.save_skinquest_trade_url(text) to authenticated;

revoke all on function public.redeem_reward(bigint) from public;
grant execute on function public.redeem_reward(bigint) to authenticated;

commit;

notify pgrst, 'reload schema';

select 'SkinQuest v12.2.10 repair applied: stable redemption restored and Trade URL save repaired.' as status;
