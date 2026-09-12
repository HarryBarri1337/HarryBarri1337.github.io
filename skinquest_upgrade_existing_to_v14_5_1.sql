-- SkinQuest v14.5.1 delta for an EXISTING v14.5.0 installation.
-- Run once in Supabase SQL Editor. Does not change existing orders or Steam sync settings.
-- Steam offer URLs remain optional; when supplied, the existing validation still applies.
-- Only an admin can run this RPC. Transition, stock and refund protections remain intact.

begin;

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

commit;

notify pgrst, 'reload schema';
