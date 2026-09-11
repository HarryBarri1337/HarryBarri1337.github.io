-- SkinQuest upgrade for EXISTING projects -> v14.3.0
-- Run once in the Supabase SQL Editor after v14.2.0 is already installed.
-- This file contains only the v14.3.0 database changes.

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
