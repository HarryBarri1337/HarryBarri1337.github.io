-- SkinQuest v14.6.0 DELTA, from v14.5.7. Back up your database first.
-- No orders, coins, history, Steam sync state or Cron jobs are reset.
begin;

create or replace function public.sq_catalog_normalize(p_text text)
returns text language sql immutable parallel safe set search_path=public as $$
 select trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
 regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
 lower(coalesce(p_text,'')), 'stat[ -]?trak[™]?', 'stattrak','g'),
 'factory[ -]+new','fn','g'), 'minimal[ -]+wear','mw','g'),
 'field[ -]+tested','ft','g'), 'well[ -]+worn','ww','g'),
 'battle[ -]+scarred','bs','g'), 'ak[ -]*47','ak47','g'),
 'm4a1[ -]*s','m4a1s','g'), 'usp[ -]*s','usps','g'), '[^a-z0-9]+',' ','g'));
$$;
create or replace function public.sq_catalog_one_typo(a text,b text)
returns boolean language plpgsql immutable parallel safe set search_path=public as $$
declare i integer:=1; j integer:=1; n integer:=length(a); m integer:=length(b); misses integer:=0;
begin
 if a=b then return true; end if;
 if n<4 or n>40 or m>40 or abs(n-m)>1 then return false; end if;
 while i<=n and j<=m loop
  if substr(a,i,1)=substr(b,j,1) then i:=i+1; j:=j+1;
  else
   misses:=misses+1; if misses>1 then return false; end if;
   if n>=m then i:=i+1; end if; if m>=n then j:=j+1; end if;
  end if;
 end loop;
 return misses+(n-i+1)+(m-j+1)<=1;
end;
$$;
create or replace function public.sq_catalog_matches(p_text text,p_query text)
returns boolean language sql immutable parallel safe set search_path=public as $$
 select not exists (
  select 1 from unnest(string_to_array(public.sq_catalog_normalize(left(p_query,120)),' ')) t(token)
  where token<>'' and not exists (
   select 1 from unnest(string_to_array(public.sq_catalog_normalize(p_text),' ')) w(word)
   where word=token or (length(token)>=3 and starts_with(word,token)) or public.sq_catalog_one_typo(token,word)
  )
 );
$$;
create or replace function public.sq_reward_family_name(p_name text)
returns text language sql immutable parallel safe set search_path=public as $$
 select trim(regexp_replace(regexp_replace(coalesce(p_name,''),
 '^(StatTrak[™]?|Souvenir)[[:space:]]+','','i'),
 '[[:space:]]*\(?((Factory New|Minimal Wear|Field-Tested|Well-Worn|Battle-Scarred)|(FN|MW|FT|WW|BS))\)?[[:space:]]*$','','i'));
$$;

-- Calculate names once per item write, not on every keystroke in a large catalogue.
alter table public.reward_items add column if not exists catalog_family_name text generated always as
 (public.sq_reward_family_name(coalesce(nullif(market_name,''),name))) stored;
alter table public.reward_items add column if not exists catalog_search_text text generated always as
 (public.sq_catalog_normalize(coalesce(name,'')||' '||coalesce(market_name,'')||' '||coalesce(condition,'')||' '||coalesce(rarity,''))) stored;
create index if not exists sq_reward_family_active_idx on public.reward_items(lower(catalog_family_name)) where active;
create or replace function public.sq_catalog_matches_normalized(p_text text,p_tokens text[])
returns boolean language plpgsql immutable parallel safe set search_path=public as $$
declare token text; word text; words text[]:=string_to_array(p_text,' '); matched boolean;
begin
 foreach token in array p_tokens loop
  if token='' or token=any(words) then continue; end if;
  matched:=false;
  foreach word in array words loop
   if (length(token)>=3 and starts_with(word,token)) or public.sq_catalog_one_typo(token,word) then matched:=true; exit; end if;
  end loop;
  if not matched then return false; end if;
 end loop;
 return true;
end;
$$;

-- Private worker; wrappers keep the old ungrouped RPC compatible.
create or replace function public.sq_catalog_page(
 p_query text,p_min_coins integer,p_max_coins integer,p_availability text,p_balance integer,
 p_sort text,p_show_out_of_stock boolean,p_limit integer,p_offset integer,p_group boolean
)
returns jsonb language sql stable security definer set search_path=public as $$
 with tokens as materialized (select string_to_array(public.sq_catalog_normalize(left(coalesce(p_query,''),120)),' ') as value), filtered as (
  select r.*,r.catalog_family_name as family_name,
   greatest(0,r.quantity_total-r.quantity_reserved) as available_stock,
   public.sq_reward_effective_fulfillment(r.fulfillment_mode,r.quantity_total,r.quantity_reserved) as current_fulfillment,
   coalesce(r.pricing_mode<>'steam' or (r.steam_price_minor>0 and r.steam_price_valid_until>now()),false) as price_is_current
  from public.reward_items r cross join tokens t
  where r.active and public.sq_catalog_matches_normalized(r.catalog_search_text,t.value)
   and (p_min_coins is null or r.points_coins>=greatest(0,p_min_coins))
   and (p_max_coins is null or r.points_coins<=greatest(0,p_max_coins))
   and (coalesce(p_show_out_of_stock,true) or r.fulfillment_mode='orderable' or r.quantity_total>r.quantity_reserved)
   and (coalesce(p_availability,'all')='all'
    or (p_availability='affordable' and r.points_coins<=greatest(0,coalesce(p_balance,0))
     and (r.fulfillment_mode='orderable' or r.quantity_total>r.quantity_reserved)
     and (r.pricing_mode<>'steam' or (r.steam_price_minor>0 and r.steam_price_valid_until>now())))
    or (p_availability='in-stock' and r.quantity_total>r.quantity_reserved)
    or (p_availability='orderable' and r.fulfillment_mode='orderable' and r.quantity_total<=r.quantity_reserved))
 ), families as (
  select f.*,
   count(*) over(partition by case when p_group then lower(family_name) else id::text end) as variant_count,
   bool_or(available_stock>0) over(partition by case when p_group then lower(family_name) else id::text end) as family_has_stock,
   row_number() over(partition by case when p_group then lower(family_name) else id::text end order by
    (available_stock>0 or fulfillment_mode='orderable') desc,price_is_current desc,points_coins,id) as member_rank
  from filtered f
 ), representatives as (select * from families where member_rank=1), ordered as (
  select f.*,row_number() over(order by
   (available_stock>0 or fulfillment_mode='orderable') desc,price_is_current desc,
   case when p_sort='starter' then (available_stock>0) end desc,
   case when p_sort in ('starter','price-asc') then points_coins end asc,
   case when p_sort='price-desc' then points_coins end desc,
   case when p_sort='stock-desc' then available_stock end desc,
   case when p_sort='featured' then sort_order end asc,lower(family_name),id) as page_rank from representatives f
 ), page as (select * from ordered where page_rank>greatest(0,coalesce(p_offset,0))
  and page_rank<=greatest(0,coalesce(p_offset,0))+greatest(1,least(coalesce(p_limit,48),60)))
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p)-'member_rank'-'page_rank' order by page_rank) from page p),'[]'::jsonb),
  'total',(select count(*) from representatives),'variant_total',(select count(*) from filtered),
  'grouped',p_group,'limit',greatest(1,least(coalesce(p_limit,48),60)),'offset',greatest(0,coalesce(p_offset,0)));
$$;
revoke all on function public.sq_catalog_page(text,integer,integer,text,integer,text,boolean,integer,integer,boolean) from public,anon,authenticated;
create or replace function public.sq_search_rewards(
 p_query text default null,p_min_coins integer default null,p_max_coins integer default null,
 p_availability text default 'all',p_balance integer default 0,p_sort text default 'starter',
 p_show_out_of_stock boolean default true,p_limit integer default 48,p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path=public as $$
 select public.sq_catalog_page(p_query,p_min_coins,p_max_coins,p_availability,p_balance,p_sort,p_show_out_of_stock,p_limit,p_offset,false);
$$;
create or replace function public.sq_browse_reward_families(
 p_query text default null,p_min_coins integer default null,p_max_coins integer default null,
 p_availability text default 'all',p_balance integer default 0,p_sort text default 'starter',
 p_show_out_of_stock boolean default true,p_limit integer default 48,p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path=public as $$
 select public.sq_catalog_page(p_query,p_min_coins,p_max_coins,p_availability,p_balance,p_sort,p_show_out_of_stock,p_limit,p_offset,true);
$$;
revoke all on function public.sq_search_rewards(text,integer,integer,text,integer,text,boolean,integer,integer) from public;
revoke all on function public.sq_browse_reward_families(text,integer,integer,text,integer,text,boolean,integer,integer) from public;
grant execute on function public.sq_search_rewards(text,integer,integer,text,integer,text,boolean,integer,integer) to anon,authenticated;
grant execute on function public.sq_browse_reward_families(text,integer,integer,text,integer,text,boolean,integer,integer) to anon,authenticated;
create or replace function public.sq_reward_details(p_reward_id bigint)
returns jsonb language sql stable security definer set search_path=public as $$
 with chosen as (select id,lower(catalog_family_name) as family
  from public.reward_items where id=p_reward_id and active), variants as (
  select r.*,r.catalog_family_name as family_name,
   greatest(0,r.quantity_total-r.quantity_reserved) as available_stock,
   public.sq_reward_effective_fulfillment(r.fulfillment_mode,r.quantity_total,r.quantity_reserved) as current_fulfillment,
   coalesce(r.pricing_mode<>'steam' or (r.steam_price_minor>0 and r.steam_price_valid_until>now()),false) as price_is_current
  from public.reward_items r,chosen c where r.active
   and lower(r.catalog_family_name)=c.family
  order by r.id=p_reward_id desc,r.points_coins,r.id limit 200)
 select case when exists(select 1 from chosen) then jsonb_build_object('selected_id',p_reward_id,
  'variants',coalesce((select jsonb_agg(to_jsonb(v) order by v.id=p_reward_id desc,v.points_coins,v.id) from variants v),'[]'::jsonb)) else null end;
$$;
revoke all on function public.sq_reward_details(bigint) from public;
grant execute on function public.sq_reward_details(bigint) to anon,authenticated;

-- Customer projections exclude staff notes, raw payloads and other users' records.
alter table public.redemption_requests add column if not exists customer_note text;
alter table public.support_requests add column if not exists related_order_id bigint references public.redemption_requests(id) on delete set null;
alter table public.support_requests add column if not exists related_coin_id bigint references public.coin_adjustments(id) on delete set null;
alter table public.support_requests add column if not exists context_snapshot jsonb not null default '{}'::jsonb;
alter table public.support_requests add column if not exists client_request_id uuid;
create unique index if not exists sq_support_client_request_idx on public.support_requests(user_id,client_request_id) where client_request_id is not null;
create index if not exists sq_support_user_created_idx on public.support_requests(user_id,created_at desc);

create or replace function public.sq_my_order(p_order_id bigint)
returns jsonb language sql stable security definer set search_path=public as $$
 select to_jsonb(r) from (select id,order_number,reward_id,reward_name,points_coins,points_cost,status,
  fulfillment_mode,estimated_ready_at,purchased_at,trade_locked_until,trade_sent_at,ready_at,completed_at,refunded_at,
  created_at,updated_at,trade_offer_url,customer_note
  from public.redemption_requests where id=p_order_id and user_id=auth.uid()) r;
$$;
revoke all on function public.sq_my_order(bigint) from public,anon;
grant execute on function public.sq_my_order(bigint) to authenticated;
create or replace function public.sq_my_coin_history(p_kind text default 'all',p_limit integer default 25,p_offset integer default 0)
returns jsonb language sql stable security definer set search_path=public as $$
 with records as (
  select c.id,c.amount,c.reason,c.source_type,c.source_id,c.created_at,
   case when c.source_type='redemption_refund' then 'refund'
    when c.source_type in ('reward_order','redemption_hold','redemption') then 'reward'
    when c.source_type in ('offerwall_credit','offerwall_reversal') or lower(coalesce(c.source_type,'')) like '%cpx%' then 'survey'
    when c.source_type in ('promo_code','promo_redemption') or c.reason like 'Promo code: %' then 'promo'
    when c.source_type in ('level_bonus','level_up_bonus','level_reward') then 'level' else 'adjustment' end as kind,
   (select r.id from public.redemption_requests r where r.user_id=auth.uid() and r.id::text=c.source_id
    and c.source_type in ('reward_order','redemption_hold','redemption','redemption_refund') limit 1) as order_id,
   case when c.source_type in ('offerwall_credit','offerwall_reversal') then left(coalesce(c.metadata->>'provider','Partner'),50) else null end as provider
  from public.coin_adjustments c where c.user_id=auth.uid()
 ), filtered as (select * from records where p_kind='all' or kind=p_kind), page as (
  select * from filtered order by created_at desc,id desc limit greatest(1,least(coalesce(p_limit,25),100)) offset greatest(0,coalesce(p_offset,0)))
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc,p.id desc) from page p),'[]'::jsonb),
  'total',(select count(*) from filtered));
$$;
revoke all on function public.sq_my_coin_history(text,integer,integer) from public,anon;
grant execute on function public.sq_my_coin_history(text,integer,integer) to authenticated;
create or replace function public.sq_my_support_context()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('orders',coalesce((select jsonb_agg(to_jsonb(r)) from
  (select id,order_number,reward_name,points_coins,status from public.redemption_requests where user_id=auth.uid() order by created_at desc,id desc limit 50) r),'[]'::jsonb),
  'transactions',coalesce((select jsonb_agg(to_jsonb(c)) from
   (select id,amount,reason,created_at from public.coin_adjustments where user_id=auth.uid() order by created_at desc,id desc limit 100) c),'[]'::jsonb),
  'tickets',coalesce((select jsonb_agg(to_jsonb(t)) from
   (select id,ticket_number,topic,status,created_at,context_snapshot from public.support_requests where user_id=auth.uid() order by created_at desc,id desc limit 25) t),'[]'::jsonb));
$$;
revoke all on function public.sq_my_support_context() from public,anon;
grant execute on function public.sq_my_support_context() to authenticated;
create or replace function public.sq_submit_linked_support(
 p_request_id uuid,p_topic text,p_message text,p_order_id bigint default null,p_coin_id bigint default null
)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare v_uid uuid:=auth.uid(); v_email text; v_ticket public.support_requests%rowtype;
 v_snapshot jsonb:='{}'::jsonb; v_order public.redemption_requests%rowtype; v_coin public.coin_adjustments%rowtype;
begin
 if v_uid is null then raise exception 'Sign in to contact support.'; end if;
 if p_request_id is null then raise exception 'A request identifier is required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('sq-support-'||v_uid::text,0));
 select * into v_ticket from public.support_requests where user_id=v_uid and client_request_id=p_request_id;
 if found then return jsonb_build_object('ok',true,'ticket_number',v_ticket.ticket_number,'id',v_ticket.id); end if;
 select case when p.contact_email_verified_at is not null then p.contact_email
  when u.email_confirmed_at is not null and u.email not like '%@steam.skinquestcs.com' then u.email else null end
 into v_email from auth.users u left join public.profiles p on p.id=u.id where u.id=v_uid;
 if coalesce(v_email,'')='' then raise exception 'Verify your contact email in Settings before contacting support.'; end if;
 if length(trim(coalesce(p_message,''))) not between 20 and 2000 then raise exception 'Write a message between 20 and 2,000 characters.'; end if;
 if p_topic not in ('Reward order','Missing coins','Survey issue','Account','Other') then raise exception 'Choose a valid support topic.'; end if;
 if (select count(*) from public.support_requests where user_id=v_uid and created_at>now()-interval '1 hour')>=5 then
  raise exception 'You have sent several requests. Please wait before sending another.'; end if;
 if p_order_id is not null then
  select * into v_order from public.redemption_requests where id=p_order_id and user_id=v_uid;
  if not found then raise exception 'That order is not available on your account.'; end if;
  v_snapshot:=v_snapshot||jsonb_build_object('order_number',v_order.order_number,'reward_name',v_order.reward_name,'coins',v_order.points_coins,'status_at_submission',v_order.status);
 end if;
 if p_coin_id is not null then
  select * into v_coin from public.coin_adjustments where id=p_coin_id and user_id=v_uid;
  if not found then raise exception 'That transaction is not available on your account.'; end if;
  v_snapshot:=v_snapshot||jsonb_build_object('transaction_id',v_coin.id,'amount',v_coin.amount,'transaction_date',v_coin.created_at);
 end if;
 insert into public.support_requests(user_id,topic,message,account_email,page_url,related_order_id,related_coin_id,context_snapshot,client_request_id)
 values(v_uid,p_topic,trim(p_message),v_email,'https://skinquestcs.com/support',p_order_id,p_coin_id,v_snapshot,p_request_id) returning * into v_ticket;
 return jsonb_build_object('ok',true,'ticket_number',v_ticket.ticket_number,'id',v_ticket.id);
end;
$$;
revoke all on function public.sq_submit_linked_support(uuid,text,text,bigint,bigint) from public,anon;
grant execute on function public.sq_submit_linked_support(uuid,text,text,bigint,bigint) to authenticated;
create or replace function public.sq_admin_order_customer_note(p_order_id bigint,p_note text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if length(coalesce(p_note,''))>2000 then raise exception 'Customer update is too long.'; end if;
 update public.redemption_requests set customer_note=nullif(trim(p_note),''),updated_at=now() where id=p_order_id;
 if not found then raise exception 'Order not found.'; end if;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'order_customer_update','reward_order',p_order_id::text,jsonb_build_object('note',left(coalesce(p_note,''),2000)));
end;
$$;
revoke all on function public.sq_admin_order_customer_note(bigint,text) from public,anon;
grant execute on function public.sq_admin_order_customer_note(bigint,text) to authenticated;

-- Manual EUR money records; not automatic provider revenue or formal accounting.
create table if not exists public.sq_finance_entries (
 id uuid primary key,
 kind text not null check(kind in ('income','expense','funding')),
 category text not null check(category in ('provider','item_purchase','fees','other')),
 amount_minor bigint not null check(amount_minor between 1 and 100000000000),
 currency text not null default 'EUR' check(currency='EUR'),
 settlement text not null check(settlement in ('expected','paid')),
 occurred_on date not null,
 provider text,
 reference text not null check(length(reference) between 1 and 120),
 note text check(length(note)<=1000),
 order_id bigint references public.redemption_requests(id) on delete set null,
 order_snapshot text,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),settled_at timestamptz,
 voided_at timestamptz,voided_by uuid references auth.users(id) on delete set null,void_reason text
);
alter table public.sq_finance_entries enable row level security;
drop policy if exists "sq finance owner read" on public.sq_finance_entries;
create policy "sq finance owner read" on public.sq_finance_entries for select to authenticated using(public.is_owner());
revoke all on public.sq_finance_entries from anon,authenticated;
grant select on public.sq_finance_entries to authenticated;
create index if not exists sq_finance_recent_idx on public.sq_finance_entries(occurred_on desc,created_at desc);
-- Active references must be unique even if requests arrive concurrently.
create unique index if not exists sq_finance_reference_idx on public.sq_finance_entries(kind,lower(reference),lower(coalesce(provider,''))) where voided_at is null;

create or replace function public.sq_owner_finance_record(
 p_id uuid,p_kind text,p_category text,p_amount_minor bigint,p_settlement text,p_occurred_on date,
 p_reference text,p_provider text default null,p_order_id bigint default null,p_note text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_entry public.sq_finance_entries%rowtype; v_number text;
begin
 if not public.is_owner() then raise exception 'Owner access required.'; end if;
 if p_id is null then raise exception 'An entry identifier is required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('sq-finance-'||p_id::text,0));
 select * into v_entry from public.sq_finance_entries where id=p_id;
 if found then
  if v_entry.kind is distinct from p_kind or v_entry.category is distinct from p_category
   or v_entry.amount_minor is distinct from p_amount_minor or v_entry.reference is distinct from trim(p_reference)
   or v_entry.provider is distinct from nullif(left(trim(p_provider),80),'') or v_entry.order_id is distinct from p_order_id
   or v_entry.occurred_on is distinct from p_occurred_on or v_entry.note is distinct from nullif(trim(p_note),'') then
   raise exception 'This identifier was already used for a different entry.'; end if;
  return to_jsonb(v_entry);
 end if;
 if p_kind not in ('income','expense','funding') or p_category not in ('provider','item_purchase','fees','other')
  or p_settlement not in ('expected','paid') then raise exception 'Choose valid finance fields.'; end if;
 if p_amount_minor is null or p_amount_minor not between 1 and 100000000000 then raise exception 'Enter a positive EUR amount.'; end if;
 if p_occurred_on is null or p_occurred_on>current_date+365 then raise exception 'Choose a valid entry date.'; end if;
 if length(trim(coalesce(p_reference,''))) not between 1 and 120 or length(coalesce(p_note,''))>1000 then raise exception 'Enter a reference and keep the note under 1,000 characters.'; end if;
 if p_category='provider' and (p_kind<>'income' or trim(coalesce(p_provider,''))='') then raise exception 'Provider income needs a provider name.'; end if;
 if p_category='item_purchase' and p_kind<>'expense' then raise exception 'Item purchases must be expenses.'; end if;
 if p_order_id is not null then
  if p_kind<>'expense' or p_category<>'item_purchase' then raise exception 'Only item purchases can be linked to an order.'; end if;
  select order_number into v_number from public.redemption_requests where id=p_order_id;
  if not found then raise exception 'Order not found.'; end if;
 end if;
 if exists(select 1 from public.sq_finance_entries where voided_at is null and kind=p_kind
  and lower(reference)=lower(trim(p_reference)) and lower(coalesce(provider,''))=lower(trim(coalesce(p_provider,'')))) then
  raise exception 'That reference already exists. Use the existing entry or a unique reference.'; end if;
 insert into public.sq_finance_entries(id,kind,category,amount_minor,settlement,occurred_on,reference,provider,order_id,order_snapshot,note,created_by,settled_at)
 values(p_id,p_kind,p_category,p_amount_minor,p_settlement,p_occurred_on,trim(p_reference),nullif(left(trim(p_provider),80),''),p_order_id,v_number,nullif(trim(p_note),''),auth.uid(),case when p_settlement='paid' then now() end) returning * into v_entry;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'finance_record','finance',p_id::text,jsonb_build_object('kind',p_kind,'amount_minor',p_amount_minor,'currency','EUR','reference',trim(p_reference)));
 return to_jsonb(v_entry);
end;
$$;
revoke all on function public.sq_owner_finance_record(uuid,text,text,bigint,text,date,text,text,bigint,text) from public,anon;
grant execute on function public.sq_owner_finance_record(uuid,text,text,bigint,text,date,text,text,bigint,text) to authenticated;
create or replace function public.sq_owner_finance_update(p_id uuid,p_action text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_entry public.sq_finance_entries%rowtype;
begin
 if not public.is_owner() then raise exception 'Owner access required.'; end if;
 select * into v_entry from public.sq_finance_entries where id=p_id for update;
 if not found then raise exception 'Entry not found.'; end if;
 if p_action='settle' then
  if v_entry.voided_at is not null then raise exception 'A voided entry cannot be settled.'; end if;
  if v_entry.settlement='paid' then return to_jsonb(v_entry); end if;
  update public.sq_finance_entries set settlement='paid',settled_at=now() where id=p_id returning * into v_entry;
 elsif p_action='void' then
  if v_entry.voided_at is not null then return to_jsonb(v_entry); end if;
  if length(trim(coalesce(p_reason,''))) not between 5 and 300 then raise exception 'Give a correction reason between 5 and 300 characters.'; end if;
  update public.sq_finance_entries set voided_at=now(),voided_by=auth.uid(),void_reason=trim(p_reason) where id=p_id returning * into v_entry;
 else raise exception 'Choose a valid finance action.'; end if;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'finance_'||p_action,'finance',p_id::text,jsonb_build_object('reason',p_reason,'amount_minor',v_entry.amount_minor));
 return to_jsonb(v_entry);
end;
$$;
revoke all on function public.sq_owner_finance_update(uuid,text,text) from public,anon;
grant execute on function public.sq_owner_finance_update(uuid,text,text) to authenticated;
create or replace function public.sq_owner_finance_dashboard(p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
 if not public.is_owner() then raise exception 'Owner access required.'; end if;
 with live as (select * from public.sq_finance_entries where voided_at is null), totals as (
  select coalesce(sum(amount_minor) filter(where kind='income' and settlement='paid'),0) as received,
   coalesce(sum(amount_minor) filter(where kind='expense' and settlement='paid'),0) as spent,
   coalesce(sum(amount_minor) filter(where kind='funding' and settlement='paid'),0) as funding,
   coalesce(sum(amount_minor) filter(where kind='income' and settlement='expected'),0) as receivable,
   coalesce(sum(amount_minor) filter(where kind='expense' and settlement='expected'),0) as payable,count(*) as recorded_count from live
 ), costs as (
  select order_id,sum(amount_minor) as amount from live where kind='expense' and category='item_purchase' and order_id is not null group by order_id
 ), open_orders as (
  select r.id,r.order_number,r.reward_name,r.points_coins,r.status,r.fulfillment_mode,c.amount as recorded_purchase_minor,
   case when i.pricing_mode='steam' and i.steam_price_minor>0 and i.steam_price_currency='EUR' and i.steam_price_valid_until>now()
    then i.steam_price_minor else null end as current_steam_estimate_minor
  from public.redemption_requests r left join public.reward_items i on i.id=r.reward_id left join costs c on c.order_id=r.id
  where r.status not in ('completed','rejected','refunded','cancelled')
 ), page as (select * from public.sq_finance_entries order by occurred_on desc,created_at desc,id limit greatest(1,least(coalesce(p_limit,50),100)) offset greatest(0,coalesce(p_offset,0)))
 select jsonb_build_object('currency','EUR','totals',(select to_jsonb(t) from totals t),
  'entries',coalesce((select jsonb_agg(to_jsonb(e) order by occurred_on desc,created_at desc,id) from page e),'[]'::jsonb),
  'total',(select count(*) from public.sq_finance_entries),
  'customer_coin_balance',(select coalesce(sum(p.points_balance),0) from public.profiles p where not exists(select 1 from public.admin_users a where a.user_id=p.id)),
  'open_orders',coalesce((select jsonb_agg(to_jsonb(o) order by o.id desc) from (select * from open_orders order by id desc limit 100) o),'[]'::jsonb),
  'open_order_count',(select count(*) from open_orders),
  'unrecorded_purchase_count',(select count(*) from open_orders where recorded_purchase_minor is null),
  'unknown_estimate_count',(select count(*) from open_orders where recorded_purchase_minor is null and current_steam_estimate_minor is null),
  'unrecorded_steam_estimate_minor',(select coalesce(sum(current_steam_estimate_minor),0) from open_orders where recorded_purchase_minor is null)) into v_result;
 return v_result;
end;
$$;
revoke all on function public.sq_owner_finance_dashboard(integer,integer) from public,anon;
grant execute on function public.sq_owner_finance_dashboard(integer,integer) to authenticated;
commit;
notify pgrst,'reload schema';
