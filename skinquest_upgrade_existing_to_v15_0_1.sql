-- SkinQuest v15.0.1: delta for an existing v15.0.0 installation.
-- Hide Sticker Slabs; preserve all saved orders, prices and inventory.
begin;
do $$ begin
 if to_regprocedure('public.sq_my_orders(text,integer,integer)') is null then
  raise exception 'Requires v15.0.0. Apply that upgrade first.';
 end if;
end $$;
create or replace function public.sq_is_excluded_reward(p_name text)
returns boolean language sql immutable set search_path=public as $$
 select coalesce(p_name,'') ~* '^[[:space:]]*sticker[[:space:]]+slab([[:space:]]|[|:]|$)';
$$;
create or replace function public.sq_hide_excluded_reward()
returns trigger language plpgsql set search_path=public as $$
begin
 if public.sq_is_excluded_reward(new.name) or public.sq_is_excluded_reward(new.market_name) then
  new.active:=false;
 end if;
 return new;
end $$;
drop trigger if exists sq_hide_excluded_reward on public.reward_items;
create trigger sq_hide_excluded_reward before insert or update on public.reward_items
 for each row execute function public.sq_hide_excluded_reward();
update public.reward_items set active=false
 where active and (public.sq_is_excluded_reward(name) or public.sq_is_excluded_reward(market_name));

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

    if v_market_name = '' or v_price <= 0 or public.sq_is_excluded_reward(v_market_name) then continue; end if;
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

commit;
notify pgrst,'reload schema';
