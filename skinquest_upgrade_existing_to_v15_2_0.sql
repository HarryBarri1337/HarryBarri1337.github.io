-- SkinQuest v15.2.0: run on an existing v15.1.0 / v15.1.1 database.
-- Repeatable, transactional. Existing paid SEK records retain their meaning.
begin;
do $$ begin
 if to_regclass('public.sq_finance_entries') is null
 or to_regclass('public.sq_deliveries') is null
 or to_regprocedure('public.sq_admin_update_order(bigint,text,text,text,timestamp with time zone)') is null then
  raise exception 'Apply the v15.1.0 setup/upgrade before this v15.2.0 upgrade.';
 end if;
end $$;

alter table public.sq_finance_entries add column if not exists payment_origin text not null default 'company';
alter table public.sq_finance_entries add column if not exists paid_by text;
alter table public.sq_finance_entries add column if not exists source_currency text not null default 'SEK';
alter table public.sq_finance_entries add column if not exists source_amount_minor bigint;
alter table public.sq_finance_entries add column if not exists fx_rate numeric(18,6) not null default 1;
alter table public.sq_finance_entries drop constraint if exists sq_finance_v1520_payment_check;
alter table public.sq_finance_entries add constraint sq_finance_v1520_payment_check check (
 settlement in ('paid','pending') and payment_origin in ('company','personal')
 and (settlement='paid' or kind='expense')
 and (payment_origin='company' or (kind='expense' and length(trim(paid_by)) between 1 and 120 and paid_by is not null))
 and source_currency in ('SEK','EUR','USD') and fx_rate>0
 and (source_amount_minor is null or source_amount_minor>0)
) not valid;
create index if not exists sq_finance_pending_idx on public.sq_finance_entries(occurred_on,id)
 where voided_at is null and settlement='pending';

create or replace function public.sq_admin_finance_save_v1520(
 p_id uuid,p_kind text,p_category text,p_amount_minor bigint,p_occurred_on date,
 p_reference text,p_external_order_id text default null,p_order_id bigint default null,p_note text default null,
 p_settlement text default 'paid',p_payment_origin text default 'company',p_paid_by text default null,
 p_source_currency text default 'SEK',p_fx_rate numeric default 1,p_expected_updated_at timestamptz default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.sq_finance_entries%rowtype; v_old jsonb; v_exists boolean; v_number text;
 v_amount bigint; v_rate numeric(18,6); v_settled timestamptz;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if p_id is null then raise exception 'An entry identifier is required.'; end if;
 if p_kind is null or p_kind not in ('income','expense','funding') then raise exception 'Choose a valid finance type.'; end if;
 if p_kind='funding' and not public.is_owner() then raise exception 'Only an owner can record owner funding.'; end if;
 if p_category is null or p_category not in ('provider','item_purchase','hosting','marketing','fees','other')
 or (p_kind='income' and p_category not in ('provider','other'))
 or (p_kind='expense' and p_category not in ('item_purchase','hosting','marketing','fees','other'))
 or (p_kind='funding' and p_category<>'other') then raise exception 'Choose a category for this finance type.'; end if;
 if p_settlement is null or p_settlement not in ('paid','pending')
 or (p_settlement='pending' and p_kind<>'expense') then raise exception 'Only expenses can be awaiting payment.'; end if;
 if p_payment_origin is null or p_payment_origin not in ('company','personal')
 or (p_payment_origin='personal' and (p_kind<>'expense' or length(trim(coalesce(p_paid_by,''))) not between 1 and 120)) then
  raise exception 'Enter who paid personally and is owed reimbursement.';
 end if;
 if p_source_currency is null or p_source_currency not in ('SEK','EUR','USD') then raise exception 'Choose SEK, EUR or USD.'; end if;
 if p_fx_rate is null or p_fx_rate::text in ('NaN','Infinity','-Infinity') or p_fx_rate<=0 or p_fx_rate>100000
 or (p_source_currency='SEK' and p_fx_rate<>1) then raise exception 'Enter the actual SEK exchange rate; SEK uses 1.'; end if;
 v_rate:=round(p_fx_rate,6);
 if v_rate<=0 or p_amount_minor is null or p_amount_minor not between 1 and 100000000000
 or round(p_amount_minor*v_rate) not between 1 and 100000000000 then raise exception 'Enter a positive amount within the supported range.'; end if;
 v_amount:=round(p_amount_minor*v_rate)::bigint;
 if p_occurred_on is null or p_occurred_on>current_date+1 then raise exception 'Use the actual purchase or payment date.'; end if;
 if length(trim(coalesce(p_reference,''))) not between 1 and 120 or length(coalesce(p_note,''))>1000
 or length(coalesce(p_external_order_id,''))>120 then raise exception 'Check the reference, invoice ID and note.'; end if;
 if p_order_id is not null then
  if p_kind<>'expense' or p_category<>'item_purchase' then raise exception 'Only reward purchases can be linked to an order.'; end if;
  select order_number into v_number from public.redemption_requests where id=p_order_id;
  if not found then raise exception 'SkinQuest order not found.'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('sq-finance-'||p_id::text,0));
 select * into e from public.sq_finance_entries where id=p_id for update;
 v_exists:=found; v_old:=case when v_exists then to_jsonb(e) end;
 if not v_exists and p_expected_updated_at is not null then raise exception 'This payment was deleted. Refresh the finance page.'; end if;
 if v_exists and not (public.is_owner() or e.created_by=auth.uid()) then raise exception 'You can only edit finance records you created.'; end if;
 if v_exists and p_expected_updated_at is not null and e.updated_at is distinct from p_expected_updated_at then
  raise exception 'This payment changed while you were editing. Refresh and reopen it.';
 end if;
 v_settled:=case when p_settlement='paid' then case when v_exists and e.settlement='paid' then coalesce(e.settled_at,now()) else now() end end;
 if v_exists then
  update public.sq_finance_entries set kind=p_kind,category=p_category,amount_minor=v_amount,currency='SEK',
   settlement=p_settlement,payment_origin=p_payment_origin,paid_by=case when p_payment_origin='personal' then trim(p_paid_by) end,
   source_currency=p_source_currency,source_amount_minor=p_amount_minor,fx_rate=v_rate,occurred_on=p_occurred_on,
   reference=trim(p_reference),external_order_id=nullif(trim(p_external_order_id),''),order_id=p_order_id,order_snapshot=v_number,
   note=nullif(trim(p_note),''),updated_by=auth.uid(),updated_at=now(),settled_at=v_settled,
   voided_at=null,voided_by=null,void_reason=null where id=p_id returning * into e;
 else
  insert into public.sq_finance_entries(id,kind,category,amount_minor,currency,settlement,payment_origin,paid_by,
   source_currency,source_amount_minor,fx_rate,occurred_on,reference,external_order_id,order_id,order_snapshot,note,created_by,updated_by,settled_at)
  values(p_id,p_kind,p_category,v_amount,'SEK',p_settlement,p_payment_origin,
   case when p_payment_origin='personal' then trim(p_paid_by) end,p_source_currency,p_amount_minor,v_rate,p_occurred_on,
   trim(p_reference),nullif(trim(p_external_order_id),''),p_order_id,v_number,nullif(trim(p_note),''),auth.uid(),auth.uid(),v_settled) returning * into e;
 end if;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),case when v_exists then 'finance_edit' else 'finance_record' end,'finance',p_id::text,
  jsonb_build_object('before',v_old,'after',to_jsonb(e)));
 return to_jsonb(e);
end $$;
revoke all on function public.sq_admin_finance_save_v1520(uuid,text,text,bigint,date,text,text,bigint,text,text,text,text,text,numeric,timestamptz) from public,anon,authenticated;
grant execute on function public.sq_admin_finance_save_v1520(uuid,text,text,bigint,date,text,text,bigint,text,text,text,text,text,numeric,timestamptz) to authenticated;

-- Old cached admin pages may add paid SEK records, but cannot silently settle new pending records.
create or replace function public.sq_admin_finance_save(
 p_id uuid,p_kind text,p_category text,p_amount_minor bigint,p_occurred_on date,
 p_reference text,p_external_order_id text default null,p_order_id bigint default null,p_note text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('sq-finance-'||p_id::text,0));
 if exists(select 1 from public.sq_finance_entries where id=p_id
   and (settlement='pending' or payment_origin='personal' or source_currency<>'SEK' or currency<>'SEK')) then
  raise exception 'Refresh the admin page before editing this payment.';
 end if;
 return public.sq_admin_finance_save_v1520(p_id,p_kind,p_category,p_amount_minor,p_occurred_on,p_reference,p_external_order_id,p_order_id,p_note);
end $$;
revoke all on function public.sq_admin_finance_save(uuid,text,text,bigint,date,text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.sq_admin_finance_save(uuid,text,text,bigint,date,text,text,bigint,text) to authenticated;

create or replace function public.sq_admin_finance_settle(p_id uuid,p_expected_updated_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.sq_finance_entries%rowtype;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('sq-finance-'||p_id::text,0));
 select * into e from public.sq_finance_entries where id=p_id for update;
 if not found or e.voided_at is not null then raise exception 'Payment not found.'; end if;
 if not (public.is_owner() or e.created_by=auth.uid()) then raise exception 'You can only settle payments you created.'; end if;
 if e.settlement='paid' then return jsonb_build_object('ok',true,'already_paid',true); end if;
 if p_expected_updated_at is not null and e.updated_at is distinct from p_expected_updated_at then
  raise exception 'This payment changed. Refresh before marking it paid.';
 end if;
 if e.kind<>'expense' or e.currency<>'SEK' or e.settlement<>'pending' then raise exception 'Only an unpaid SEK cost can be settled.'; end if;
 update public.sq_finance_entries set settlement='paid',settled_at=now(),updated_at=now(),updated_by=auth.uid() where id=p_id;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'finance_settled','finance',p_id::text,jsonb_build_object('amount_minor',e.amount_minor,'paid_by',e.paid_by,'payment_origin',e.payment_origin));
 return jsonb_build_object('ok',true,'already_paid',false);
end $$;
revoke all on function public.sq_admin_finance_settle(uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.sq_admin_finance_settle(uuid,timestamptz) to authenticated;

create or replace function public.sq_admin_finance_dashboard_v1520(p_limit integer default 50,p_offset integer default 0,p_filter text default 'all')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if p_filter is null or p_filter not in ('all','paid','pending') then raise exception 'Choose a payment filter.'; end if;
 with live as (select * from public.sq_finance_entries where voided_at is null and currency='SEK'), totals as (
  select coalesce(sum(amount_minor) filter(where kind='income' and settlement<>'pending'),0) as income,
   coalesce(sum(amount_minor) filter(where kind='expense'),0) as expenses,
   coalesce(sum(amount_minor) filter(where kind='expense' and settlement<>'pending'),0) as cash_expenses,
   coalesce(sum(amount_minor) filter(where kind='funding' and settlement<>'pending'),0) as funding,
   coalesce(sum(amount_minor) filter(where kind='expense' and settlement='pending'),0) as unpaid,
   coalesce(sum(amount_minor) filter(where kind='expense' and settlement='pending' and payment_origin='personal'),0) as reimbursements,
   count(*) filter(where settlement='pending') as unpaid_count,count(*) as recorded_count from live
 ), costs as (select order_id,sum(amount_minor) as amount from live where kind='expense' and category='item_purchase' and order_id is not null group by order_id),
 open_orders as (select r.id,r.order_number,r.reward_name,r.points_coins,r.status,r.fulfillment_mode,c.amount as recorded_purchase_minor
  from public.redemption_requests r left join costs c on c.order_id=r.id where r.status not in ('completed','rejected','refunded','cancelled')),
 filtered as (select * from public.sq_finance_entries where voided_at is null and (p_filter='all' or settlement=p_filter)),
 page as (select * from filtered order by occurred_on desc,created_at desc,id limit greatest(1,least(coalesce(p_limit,50),100)) offset greatest(0,coalesce(p_offset,0))),
 payees as (select min(paid_by) as paid_by,sum(amount_minor) as amount_minor,count(*) as count from live
  where settlement='pending' and payment_origin='personal' group by lower(trim(paid_by)))
 select jsonb_build_object('currency','SEK','totals',(select to_jsonb(t) from totals t),
  'entries',coalesce((select jsonb_agg(to_jsonb(e) order by occurred_on desc,created_at desc,id) from page e),'[]'::jsonb),
  'total',(select count(*) from filtered),'legacy_currency_count',(select count(*) from public.sq_finance_entries where voided_at is null and currency<>'SEK'),
  'payees',coalesce((select jsonb_agg(to_jsonb(p) order by paid_by) from payees p),'[]'::jsonb),
  'customer_coin_balance',(select coalesce(sum(p.points_balance),0) from public.profiles p where not exists(select 1 from public.admin_users a where a.user_id=p.id)),
  'open_orders',coalesce((select jsonb_agg(to_jsonb(o) order by o.id desc) from (select * from open_orders order by id desc limit 100) o),'[]'::jsonb),
  'open_order_count',(select count(*) from open_orders),'unrecorded_purchase_count',(select count(*) from open_orders where recorded_purchase_minor is null)) into v_result;
 return v_result;
end $$;
revoke all on function public.sq_admin_finance_dashboard_v1520(integer,integer,text) from public,anon,authenticated;
grant execute on function public.sq_admin_finance_dashboard_v1520(integer,integer,text) to authenticated;
-- Preserve the old dashboard contract: expenses means cash expenses on old clients.
create or replace function public.sq_admin_finance_dashboard(p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare j jsonb;
begin
 j:=public.sq_admin_finance_dashboard_v1520(p_limit,p_offset,'all');
 return jsonb_set(j,'{totals,expenses}',j#>'{totals,cash_expenses}');
end $$;
revoke all on function public.sq_admin_finance_dashboard(integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_finance_dashboard(integer,integer) to authenticated;

-- DELIVERY_V1520: customer-complete queues and atomic fulfilment functions follow.
create or replace function public.sq_admin_delivery_orders(p_limit integer default 100,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(t)) from
  (select r.*,p.username,p.steam_name,p.contact_email,p.steam_trade_url as current_trade_url,
    (r.status<>'trade_sent' and r.steam_trade_url is distinct from p.steam_trade_url) as trade_url_needs_review,
    d.label as delivery_label,
    (select count(*) from public.redemption_requests x where x.delivery_id=r.delivery_id
      and x.status not in ('completed','rejected','refunded','cancelled')) as delivery_total
   from public.redemption_requests r left join public.profiles p on p.id=r.user_id
    left join public.sq_deliveries d on d.id=r.delivery_id
   where r.status not in ('completed','rejected','refunded','cancelled')
   order by r.created_at,r.id limit greatest(1,least(coalesce(p_limit,100),1000)) offset greatest(0,coalesce(p_offset,0))) t),'[]'::jsonb),
  'total',(select count(*) from public.redemption_requests where status not in ('completed','rejected','refunded','cancelled')));
end $$;
revoke all on function public.sq_admin_delivery_orders(integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_delivery_orders(integer,integer) to authenticated;

create or replace function public.sq_admin_delivery_queue(p_search text default null,p_filter text default 'all',p_limit integer default 40,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare j jsonb; v_search text:=nullif(lower(trim(p_search)),'');
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if length(coalesce(v_search,''))>120 or p_filter is null or p_filter not in ('all','ready','purchase','locked','sent','review') then raise exception 'Choose a valid delivery filter.'; end if;
 with base as (
  select r.*,p.username,p.steam_name,p.contact_email,p.steam_trade_url as current_trade_url,d.label as delivery_label,
   (r.status<>'trade_sent' and r.steam_trade_url is distinct from p.steam_trade_url) as trade_url_needs_review,
   (r.status='ready_to_trade' or (r.status in ('pending','reviewing','ordered') and r.fulfillment_mode='stocked')
    or (r.status='trade_locked' and r.trade_locked_until<=now())) as sendable,
   (r.fulfillment_mode='orderable' and r.status in ('pending','reviewing','ordered')) as needs_purchase
  from public.redemption_requests r left join public.profiles p on p.id=r.user_id left join public.sq_deliveries d on d.id=r.delivery_id
  where r.status not in ('completed','rejected','refunded','cancelled')
 ), customers as (
  select user_id,min(coalesce(steam_name,username,user_id::text)) as name,min(contact_email) as email,
   min(created_at) as oldest_at,count(*) as order_count,
   count(*) filter(where sendable and not trade_url_needs_review) as ready_count,
   count(*) filter(where needs_purchase) as purchase_count,
   count(*) filter(where status='trade_locked' and (trade_locked_until is null or trade_locked_until>now())) as locked_count,
   count(*) filter(where status='trade_sent') as sent_count,count(*) filter(where trade_url_needs_review) as review_count,
   bool_or(v_search is null or position(v_search in lower(concat_ws(' ',username,steam_name,contact_email,user_id::text,order_number,reward_name,delivery_label)))>0) as matches_search
  from base group by user_id
 ), filtered as (select * from customers where matches_search and (p_filter='all' or (p_filter='ready' and ready_count>0)
  or (p_filter='purchase' and purchase_count>0) or (p_filter='locked' and locked_count>0)
  or (p_filter='sent' and sent_count>0) or (p_filter='review' and review_count>0))),
 page as (select * from filtered order by (ready_count>0) desc,(purchase_count>0) desc,(sent_count>0) desc,oldest_at,user_id limit greatest(1,least(coalesce(p_limit,40),100)) offset greatest(0,coalesce(p_offset,0))),
 complete_customers as (select c.*,coalesce((select jsonb_agg(to_jsonb(b) order by b.delivery_id nulls first,b.created_at,b.id) from base b where b.user_id=c.user_id),'[]'::jsonb) as items from page c)
 select jsonb_build_object('customers',coalesce((select jsonb_agg(to_jsonb(c) order by (ready_count>0) desc,(purchase_count>0) desc,(sent_count>0) desc,oldest_at,user_id) from complete_customers c),'[]'::jsonb),
  'total',(select count(*) from filtered),'stats',jsonb_build_object('customers',(select count(*) from customers),'orders',(select count(*) from base),
   'ready',(select count(*) from base where sendable and not trade_url_needs_review),'purchase',(select count(*) from base where needs_purchase),
   'locked',(select count(*) from base where status='trade_locked' and (trade_locked_until is null or trade_locked_until>now())),
   'sent',(select count(*) from base where status='trade_sent'),'review',(select count(*) from base where trade_url_needs_review))) into j;
 return j;
end $$;
revoke all on function public.sq_admin_delivery_queue(text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_delivery_queue(text,text,integer,integer) to authenticated;

-- All writes lock profile -> deliveries -> orders. This also serializes address changes.
create or replace function public.sq_lock_fulfilment_orders(p_ids bigint[],p_expected jsonb default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_count integer;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if cardinality(p_ids) is null or cardinality(p_ids) not between 1 and 100
 or cardinality(p_ids)<>(select count(distinct x) from unnest(p_ids) x) then raise exception 'Select 1–100 distinct orders.'; end if;
 select count(*),min(user_id::text)::uuid into v_count,v_user from public.redemption_requests where id=any(p_ids);
 if v_count<>cardinality(p_ids) or (select count(distinct user_id) from public.redemption_requests where id=any(p_ids))<>1 then
  raise exception 'Select orders belonging to one customer.';
 end if;
 perform id from public.profiles where id=v_user for update;
 if not found then raise exception 'Customer profile not found.'; end if;
 perform id from public.sq_deliveries where id in (select delivery_id from public.redemption_requests where id=any(p_ids)) order by id for update;
 perform id from public.redemption_requests where id=any(p_ids) order by id for update;
 if exists(select 1 from public.redemption_requests where id=any(p_ids) and status in ('completed','rejected','refunded','cancelled')) then
  raise exception 'An order was closed. Refresh this customer before continuing.';
 end if;
 if p_expected is not null and exists(select 1 from public.redemption_requests r where id=any(p_ids) and
  (r.status is distinct from p_expected->r.id::text->>'status' or r.updated_at is distinct from (p_expected->r.id::text->>'updated_at')::timestamptz)) then
  raise exception 'These orders changed. Refresh this customer before continuing.';
 end if;
 return v_user;
end $$;
revoke all on function public.sq_lock_fulfilment_orders(bigint[],jsonb) from public,anon,authenticated;

create or replace function public.sq_admin_set_delivery(p_order_ids bigint[],p_split boolean default false,p_expected jsonb default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_id uuid;
begin
 v_user:=public.sq_lock_fulfilment_orders(p_order_ids,p_expected);
 if not coalesce(p_split,false) and cardinality(p_order_ids)<2 then raise exception 'Select at least two orders for a shared delivery.'; end if;
 if exists(select 1 from public.redemption_requests r where (r.id=any(p_order_ids)
  or r.delivery_id in (select delivery_id from public.redemption_requests where id=any(p_order_ids)))
  and (r.status in ('trade_sent','completed') or r.trade_sent_at is not null)) then raise exception 'Sent deliveries keep their original item list.'; end if;
 if exists(select 1 from public.redemption_requests r where r.delivery_id in
  (select delivery_id from public.redemption_requests where id=any(p_order_ids))
  and r.status not in ('completed','rejected','refunded','cancelled') and not r.id=any(p_order_ids)) then
  raise exception 'Select every active item in a shared delivery before regrouping it.';
 end if;
 if not coalesce(p_split,false) then
  insert into public.sq_deliveries(user_id,label,created_by) values(v_user,'Steam delivery',auth.uid()) returning id into v_id;
 end if;
 update public.redemption_requests set delivery_id=v_id,updated_at=now() where id=any(p_order_ids);
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),case when coalesce(p_split,false) then 'delivery_split' else 'delivery_created' end,'delivery',coalesce(v_id::text,v_user::text),jsonb_build_object('orders',p_order_ids,'user_id',v_user));
 return jsonb_build_object('ok',true,'delivery_id',v_id,'count',cardinality(p_order_ids));
end $$;
revoke all on function public.sq_admin_set_delivery(bigint[],boolean,jsonb) from public,anon,authenticated;
grant execute on function public.sq_admin_set_delivery(bigint[],boolean,jsonb) to authenticated;

create or replace function public.sq_admin_create_delivery(p_order_ids bigint[],p_label text default 'Steam delivery')
returns jsonb language plpgsql security definer set search_path=public as $$
declare j jsonb;
begin
 if length(trim(coalesce(p_label,'')))>100 then raise exception 'Delivery label is too long.'; end if;
 j:=public.sq_admin_set_delivery(p_order_ids,false,null);
 update public.sq_deliveries set label=coalesce(nullif(trim(p_label),''),'Steam delivery') where id=(j->>'delivery_id')::uuid;
 return j;
end $$;
revoke all on function public.sq_admin_create_delivery(bigint[],text) from public,anon,authenticated;
grant execute on function public.sq_admin_create_delivery(bigint[],text) to authenticated;

create or replace function public.sq_admin_fulfil_orders(p_order_ids bigint[],p_action text,p_lock_until timestamptz default null,p_trade_offer_url text default null,p_expected jsonb default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid; r public.redemption_requests%rowtype; v_count int:=0; v_ids bigint[]:='{}'; v_target text; v_delivery uuid; v_groups int; p public.profiles%rowtype;
begin
 v_user:=public.sq_lock_fulfilment_orders(p_order_ids,p_expected);
 if p_action is null or p_action not in ('reviewing','ordered','trade_locked','ready_to_trade','trade_sent','completed') then raise exception 'Choose a fulfilment action.'; end if;
 if p_action='trade_locked' and (p_lock_until is null or not isfinite(p_lock_until) or p_lock_until<=now()) then raise exception 'Enter the future tradable time shown by Steam.'; end if;
 if p_action in ('trade_sent','completed') and exists(select 1 from public.redemption_requests x where x.delivery_id in
  (select delivery_id from public.redemption_requests where id=any(p_order_ids)) and x.status not in ('completed','rejected','refunded','cancelled') and not x.id=any(p_order_ids)) then
  raise exception 'Select all active items in the shared offer.';
 end if;
 if p_action='trade_sent' then
  select * into p from public.profiles where id=v_user;
  if p.steam_trade_url is null or p.steam_trade_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?'
  or p.steam_trade_url !~ '(^|[?&])partner=[0-9]+(&|$)' or p.steam_trade_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)' then raise exception 'A valid Steam trade link is required.'; end if;
  if p.steam_id ~ '^[0-9]+$' and substring(p.steam_trade_url from '[?&]partner=([0-9]+)')::numeric<>p.steam_id::numeric-76561197960265728::numeric then raise exception 'Trade link does not match the customer Steam account.'; end if;
  if exists(select 1 from public.redemption_requests where id=any(p_order_ids) and steam_trade_url is distinct from p.steam_trade_url) then raise exception 'Review the changed trade link before marking sent.'; end if;
  if exists(select 1 from public.redemption_requests where id=any(p_order_ids) and not
   (status='ready_to_trade' or (status in ('pending','reviewing','ordered') and fulfillment_mode='stocked')
    or (status='trade_locked' and trade_locked_until<=now()))) then raise exception 'Every selected item must be available before sending one offer.'; end if;
  select count(distinct delivery_id) into v_groups from public.redemption_requests where id=any(p_order_ids);
  if cardinality(p_order_ids)>1 and (v_groups<>1 or exists(select 1 from public.redemption_requests where id=any(p_order_ids) and delivery_id is null)) then
   v_delivery:=(public.sq_admin_set_delivery(p_order_ids,false,null)->>'delivery_id')::uuid;
  end if;
 elsif p_action='completed' and exists(select 1 from public.redemption_requests where id=any(p_order_ids) and status<>'trade_sent') then
  raise exception 'Only sent offers can be recorded as accepted.';
 end if;
 for r in select * from public.redemption_requests where id=any(p_order_ids) order by id loop
  v_target:=null;
  if p_action='reviewing' and r.status='pending' then v_target:='reviewing';
  elsif p_action='ordered' and r.fulfillment_mode='orderable' and r.status in ('pending','reviewing') then v_target:='ordered';
  elsif p_action='trade_locked' and r.fulfillment_mode='orderable' and r.status in ('pending','reviewing','ordered') then
   if r.status<>'ordered' then perform public.sq_admin_update_order(r.id,'ordered',r.admin_note,null,null); end if;
   v_target:='trade_locked';
  elsif p_action='ready_to_trade' and ((r.status in ('pending','reviewing','ordered') and r.fulfillment_mode='stocked') or (r.status='trade_locked' and r.trade_locked_until<=now())) then v_target:='ready_to_trade';
  elsif p_action='trade_sent' then
   if r.status<>'ready_to_trade' then perform public.sq_admin_update_order(r.id,'ready_to_trade',r.admin_note,null,null); end if;
   v_target:='trade_sent';
  elsif p_action='completed' then v_target:='completed';
  end if;
  if v_target is not null then
   perform public.sq_admin_update_order(r.id,v_target,r.admin_note,case when p_action='trade_sent' then p_trade_offer_url end,case when v_target='trade_locked' then p_lock_until end);
   v_count:=v_count+1;v_ids:=array_append(v_ids,r.id);
  end if;
 end loop;
 if v_count=0 then raise exception 'No selected items need this step. Refresh the customer.'; end if;
 return jsonb_build_object('ok',true,'count',v_count,'skipped',cardinality(p_order_ids)-v_count,'changed_ids',v_ids,'delivery_id',v_delivery);
end $$;
revoke all on function public.sq_admin_fulfil_orders(bigint[],text,timestamptz,text,jsonb) from public,anon,authenticated;
grant execute on function public.sq_admin_fulfil_orders(bigint[],text,timestamptz,text,jsonb) to authenticated;

create or replace function public.sq_admin_review_order_trade_urls(p_order_ids bigint[],p_expected_url text,p_expected jsonb default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_id bigint; n int:=0;
begin
 v_user:=public.sq_lock_fulfilment_orders(p_order_ids,p_expected);
 if p_expected_url is null or p_expected_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?'
 or p_expected_url !~ '(^|[?&])partner=[0-9]+(&|$)' or p_expected_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)' then raise exception 'A valid current trade link is required.'; end if;
 for v_id in select id from public.redemption_requests where id=any(p_order_ids) and status<>'trade_sent' order by id loop
  perform public.sq_admin_review_trade_url(v_id,p_expected_url);n:=n+1;
 end loop;
 if n=0 then raise exception 'Select unsent items for trade-link review.'; end if;
 return jsonb_build_object('ok',true,'count',n);
end $$;
revoke all on function public.sq_admin_review_order_trade_urls(bigint[],text,jsonb) from public,anon,authenticated;
grant execute on function public.sq_admin_review_order_trade_urls(bigint[],text,jsonb) to authenticated;

-- Legacy grouped controls now use the same mixed-stage, atomic implementation.
create or replace function public.sq_admin_delivery_update(p_delivery_id uuid,p_status text,p_lock_until timestamptz default null,p_trade_offer_url text default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ids bigint[]; j jsonb; v_id bigint;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if length(coalesce(p_note,''))>2000 then raise exception 'Customer update too long.'; end if;
 perform p.id from public.profiles p join public.sq_deliveries d on d.user_id=p.id where d.id=p_delivery_id for update of p;
 perform id from public.sq_deliveries where id=p_delivery_id for update;
 select array_agg(id order by id) into ids from public.redemption_requests where delivery_id=p_delivery_id and status not in ('completed','rejected','refunded','cancelled');
 j:=public.sq_admin_fulfil_orders(ids,p_status,p_lock_until,p_trade_offer_url,null);
 if p_note is not null then for v_id in select unnest(ids) loop perform public.sq_admin_order_customer_note(v_id,p_note); end loop; end if;
 return j;
end $$;
revoke all on function public.sq_admin_delivery_update(uuid,text,timestamptz,text,text) from public,anon,authenticated;
grant execute on function public.sq_admin_delivery_update(uuid,text,timestamptz,text,text) to authenticated;

commit;
notify pgrst,'reload schema';
