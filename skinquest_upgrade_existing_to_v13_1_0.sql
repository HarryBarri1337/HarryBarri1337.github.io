-- SkinQuest existing-project upgrade v13.1.0
-- Run once after v13.0.0. Safe to run again.
-- Adds BitLabs callback accounting and prevents redemption refunds from XP.

begin;

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
  if v_user_id is null then raise exception 'You must be logged in.'; end if;
  perform public.ensure_skinquest_profile();
  select * into v_profile from public.profiles where id = v_user_id for update;

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
      'Level reward / Level ' || (v_claimed_level + 1)::text ||
        case when v_current_level > v_claimed_level + 1 then ' to ' || v_current_level::text else '' end,
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

  insert into public.offerwall_events (
    provider, provider_event_id, user_id, amount, status, raw_payload, processed_at
  ) values (
    'bitlabs', p_event_id, p_user_id, p_amount,
    case when p_amount > 0 then 'completed' else 'reversed' end,
    coalesce(p_payload, '{}'::jsonb), now()
  ) on conflict (provider, provider_event_id) do nothing
  returning id into v_event_id;

  if v_event_id is null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'event_id', p_event_id);
  end if;

  insert into public.profiles (id, username) values (p_user_id, 'user') on conflict (id) do nothing;
  select coalesce(points_balance, 0) into v_balance from public.profiles where id = p_user_id for update;
  update public.profiles
    set points_balance = greatest(0, coalesce(points_balance, 0) + p_amount),
        account_status = case
          when p_amount < 0 and coalesce(v_balance, 0) < (p_amount * -1) then 'under_review'
          else account_status
        end
    where id = p_user_id;

  insert into public.coin_adjustments (user_id, amount, reason, source_type, source_id, metadata)
  values (
    p_user_id,
    p_amount,
    case when p_amount > 0 then 'BitLabs survey completion' else 'BitLabs survey reconciliation' end,
    case when p_amount > 0 then 'offerwall_credit' else 'offerwall_reversal' end,
    'bitlabs:' || p_event_id,
    jsonb_build_object('provider', 'bitlabs', 'reference_id', p_reference_id)
  );

  return jsonb_build_object(
    'ok', true,
    'duplicate', false,
    'event_id', p_event_id,
    'amount', p_amount
  );
end;
$$;

revoke all on function public.process_bitlabs_callback(text, uuid, integer, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.process_bitlabs_callback(text, uuid, integer, text, jsonb)
  to service_role;
grant execute on function public.claim_level_rewards() to authenticated;

commit;
