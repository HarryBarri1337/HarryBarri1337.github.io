-- SkinQuest existing-project repair v13.0.0
-- Run this once on the CURRENT Supabase project.
-- Repairs the missing redemption_requests.reward_id column that prevents all
-- reward claims, then restores the stable redemption and Trade URL functions.

begin;

alter table public.profiles add column if not exists steam_trade_url text;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

-- Existing projects created before reward inventory linking can be missing this
-- column. redeem_reward always writes it, so its absence rolls back every claim.
alter table public.redemption_requests
  add column if not exists reward_id bigint
  references public.reward_items(id) on delete set null;
alter table public.reward_items add column if not exists max_per_user integer;
alter table public.redemption_requests add column if not exists admin_notified_at timestamptz;
alter table public.redemption_requests add column if not exists user_notified_at timestamptz;

create table if not exists public.support_rate_limits (
  key_hash text not null,
  window_start timestamptz not null,
  request_count integer not null default 0,
  primary key (key_hash, window_start)
);

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
    select count(*) into v_user_redemptions from public.redemption_requests
    where user_id = v_user_id and reward_id = v_reward.id
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


-- The frontend normally uses the security-definer RPC. This restricted policy
-- is only a fallback for the authenticated user's own steam_trade_url column.
alter table public.profiles enable row level security;
drop policy if exists profiles_update_own_trade_url on public.profiles;
create policy profiles_update_own_trade_url on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

grant select on public.profiles to authenticated;
revoke update (steam_trade_url) on public.profiles from authenticated;

revoke all on function public.save_skinquest_trade_url(text) from public;
grant execute on function public.save_skinquest_trade_url(text) to authenticated;

revoke all on function public.redeem_reward(bigint) from public;
grant execute on function public.redeem_reward(bigint) to authenticated;

create or replace function public.process_offerwall_postback(
  p_provider text, p_event_id text, p_user_id uuid, p_amount integer,
  p_status text, p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_event public.offerwall_events%rowtype; v_previous text; v_balance integer;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required.'; end if;
  p_provider := lower(trim(p_provider)); p_status := lower(trim(p_status));
  if p_provider not in ('cpx', 'bitlabs', 'lootably') then raise exception 'Unsupported provider.'; end if;
  if p_event_id is null or char_length(p_event_id) > 180 then raise exception 'Invalid event id.'; end if;
  if p_amount < 0 or p_amount > 100000 then raise exception 'Invalid coin amount.'; end if;
  if p_status not in ('pending', 'completed', 'reversed', 'rejected') then raise exception 'Invalid status.'; end if;
  perform 1 from auth.users where id = p_user_id; if not found then raise exception 'Unknown user.'; end if;
  select * into v_event from public.offerwall_events where provider=p_provider and provider_event_id=p_event_id for update;
  if not found then
    insert into public.offerwall_events(provider,provider_event_id,user_id,amount,status,raw_payload,processed_at)
    values(p_provider,p_event_id,p_user_id,p_amount,'pending',coalesce(p_payload,'{}'::jsonb),now()) returning * into v_event;
  elsif v_event.user_id is distinct from p_user_id or v_event.amount is distinct from p_amount then
    raise exception 'Postback does not match the original event.';
  end if;
  v_previous := v_event.status;
  if p_status='completed' and v_previous<>'completed' then
    insert into public.profiles(id,username) values(p_user_id,'user') on conflict(id) do nothing;
    update public.profiles set points_balance=coalesce(points_balance,0)+p_amount where id=p_user_id;
    insert into public.coin_adjustments(user_id,amount,reason,source_type,source_id,metadata)
    values(p_user_id,p_amount,initcap(p_provider)||' survey completion','offerwall_credit',p_provider||':'||p_event_id,jsonb_build_object('provider',p_provider));
  elsif p_status in ('reversed','rejected') and v_previous='completed' then
    select coalesce(points_balance,0) into v_balance from public.profiles where id=p_user_id for update;
    update public.profiles set points_balance=greatest(0,coalesce(points_balance,0)-p_amount), account_status=case when coalesce(v_balance,0)<p_amount then 'under_review' else account_status end where id=p_user_id;
    insert into public.coin_adjustments(user_id,amount,reason,source_type,source_id,metadata)
    values(p_user_id,-p_amount,initcap(p_provider)||' survey reversal','offerwall_reversal',p_provider||':'||p_event_id,jsonb_build_object('provider',p_provider));
  end if;
  update public.offerwall_events set status=p_status,raw_payload=coalesce(p_payload,raw_payload),processed_at=now() where id=v_event.id;
  return jsonb_build_object('ok',true,'event_id',v_event.id,'previous_status',v_previous,'status',p_status);
end $$;

revoke all on function public.process_offerwall_postback(text,text,uuid,integer,text,jsonb) from public, anon, authenticated;
grant execute on function public.process_offerwall_postback(text,text,uuid,integer,text,jsonb) to service_role;
drop policy if exists support_requests_insert_own on public.support_requests;
drop policy if exists support_requests_insert_contact on public.support_requests;
revoke insert on public.support_requests from anon, authenticated;
revoke usage, select on public.support_requests_id_seq from anon;
drop policy if exists profiles_update_own_trade_url on public.profiles;
revoke update (steam_trade_url) on public.profiles from authenticated;
alter table public.support_rate_limits enable row level security;
revoke all on public.support_rate_limits from public, anon, authenticated;
update public.reward_items set active=false where lower(name)='galil ar | blue titanium' and coalesce(nullif(points_coins,0),points_cost,0)<=1;
update public.reward_items set name=replace(name,'Dreams & Nightmare Case','Dreams & Nightmares Case') where name like '%Dreams & Nightmare Case%';
do $$ begin if not exists(select 1 from pg_constraint where conname='redemption_trade_offer_url_safe') then
  alter table public.redemption_requests add constraint redemption_trade_offer_url_safe check(trade_offer_url is null or trade_offer_url ~* '^https://(www\.)?steamcommunity\.com/tradeoffer/') not valid;
end if; end $$;
do $$ begin if not exists(select 1 from pg_constraint where conname='profiles_steam_trade_url_safe') then
  alter table public.profiles add constraint profiles_steam_trade_url_safe check(steam_trade_url is null or steam_trade_url ~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?.*partner=[0-9]+.*token=[A-Za-z0-9_-]+') not valid;
end if; end $$;

commit;

notify pgrst, 'reload schema';

select 'SkinQuest v13.0.0 repair applied: reward claims, Trade URL save, and redemption schema repaired.' as status;
