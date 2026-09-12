-- SkinQuest existing-database upgrade: v14.5.1 -> v14.5.2
-- Run this file once in Supabase SQL Editor after taking a database backup.
-- Do not run the full-setup file on an existing project.

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
