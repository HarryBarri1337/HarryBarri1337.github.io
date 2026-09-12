-- SkinQuest upgrade for EXISTING projects -> v14.5.0
-- Run ONCE after v14.4.1. This file contains only v14.5.0 database changes.
-- Steam catalog requests are performed by the steam-market-sync Edge Function;
-- the browser never calls Steam directly and never receives a service key.

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
