-- SkinQuest upgrade for EXISTING projects -> v14.4.1
-- Run ONCE after v14.3.0. This file contains only v14.4.1 database changes.
-- v14.4.1 introduces stocked vs orderable rewards, trade-lock countdowns,
-- a clearer order lifecycle, and safe stock/refund accounting for both modes.

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

  if v_status = 'trade_sent' and coalesce(v_final_trade_url, '') = '' then
    raise exception 'A Steam trade-offer URL is required before marking the order as Trade sent.';
  end if;
  if v_status = 'completed' then
    if v_old_status <> 'trade_sent' then raise exception 'Mark the order Trade sent before completing it.'; end if;
    if coalesce(v_final_trade_url, '') = '' then raise exception 'A Steam trade-offer URL is required before completing the order.'; end if;
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
