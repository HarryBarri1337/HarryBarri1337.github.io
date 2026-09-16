-- SkinQuest v15.0.0: ONLY the delta for an existing v14.6.2 database.
-- Back up first. Transactional and repeatable. No customer coins are migrated.
begin;
do $$ begin
 if to_regprocedure('public.sq_process_timewall_postback(text,uuid,integer,text)') is null
 or to_regprocedure('public.sq_my_order(bigint)') is null then
  raise exception 'Upgrade requires the v14.6.2 schema.';
 end if;
end $$;

create table if not exists public.sq_deliveries (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 label text not null default 'Steam delivery' check(length(label) between 1 and 100),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);
alter table public.sq_deliveries enable row level security;
alter table public.sq_deliveries add column if not exists user_notice_signature text;
alter table public.sq_deliveries add column if not exists admin_notice_signature text;
revoke all on public.sq_deliveries from public,anon,authenticated;
grant select,update on public.sq_deliveries to service_role;
alter table public.redemption_requests add column if not exists delivery_id uuid references public.sq_deliveries(id) on delete set null;
alter table public.redemption_requests add column if not exists trade_url_changed_at timestamptz;
alter table public.redemption_requests add column if not exists trade_url_reviewed_at timestamptz;
create index if not exists sq_orders_delivery_idx on public.redemption_requests(delivery_id);

create or replace function public.sq_flag_changed_trade_url()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.steam_trade_url is distinct from old.steam_trade_url then
  update public.redemption_requests set trade_url_changed_at=now(),trade_url_reviewed_at=null,updated_at=now()
  where user_id=new.id and status in ('pending','reviewing','ordered','trade_locked','ready_to_trade')
   and steam_trade_url is distinct from new.steam_trade_url;
 end if;
 return new;
end $$;
drop trigger if exists sq_flag_changed_trade_url on public.profiles;
create trigger sq_flag_changed_trade_url after update of steam_trade_url on public.profiles
 for each row execute function public.sq_flag_changed_trade_url();
-- Flag old outstanding mismatches as well. Never rewrite a sent offer's snapshot.
update public.redemption_requests r set trade_url_changed_at=coalesce(r.trade_url_changed_at,now()),trade_url_reviewed_at=null
from public.profiles p where p.id=r.user_id
 and r.status in ('pending','reviewing','ordered','trade_locked','ready_to_trade')
 and r.steam_trade_url is distinct from p.steam_trade_url;

create or replace function public.sq_admin_review_trade_url(p_order_id bigint,p_expected_url text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.redemption_requests%rowtype; p public.profiles%rowtype;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 -- Lock the profile before the order, matching the profile-change trigger.
 select p1.* into p from public.profiles p1 join public.redemption_requests r1 on r1.user_id=p1.id
  where r1.id=p_order_id for update of p1;
 select * into r from public.redemption_requests where id=p_order_id for update;
 if not found then raise exception 'Order not found.'; end if;
 if r.status not in ('pending','reviewing','ordered','trade_locked','ready_to_trade') then
  raise exception 'Sent or closed orders retain their original trade URL.';
 end if;
 if p.steam_trade_url is null or p.steam_trade_url is distinct from p_expected_url
 or p.steam_trade_url !~ '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?.*' then
  raise exception 'Trade URL changed again or is missing. Refresh before reviewing.';
 end if;
 if p.steam_id ~ '^[0-9]+$' and
  coalesce(substring(p.steam_trade_url from '[?&]partner=([0-9]+)')::numeric,-1)
   <> p.steam_id::numeric-76561197960265728::numeric then
  raise exception 'Trade URL does not match the connected Steam account.';
 end if;
 update public.redemption_requests set steam_trade_url=p.steam_trade_url,
  trade_url_reviewed_at=now(),updated_at=now() where id=r.id;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'trade_url_reviewed','redemption_request',r.id::text,jsonb_build_object('order_number',r.order_number));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.sq_admin_review_trade_url(bigint,text) from public,anon;
grant execute on function public.sq_admin_review_trade_url(bigint,text) to authenticated;

create or replace function public.sq_admin_create_delivery(p_order_ids bigint[],p_label text default 'Steam delivery')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid; v_id uuid; v_count int; v_expected int;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 v_expected:=cardinality(p_order_ids);
 if v_expected is null or v_expected<1 or v_expected>100
 or v_expected<>(select count(distinct x) from unnest(p_order_ids) x) then
  raise exception 'Select 1–100 distinct orders.';
 end if;
 perform id from public.redemption_requests where id=any(p_order_ids) order by id for update;
 select count(*),min(user_id::text)::uuid into v_count,v_user from public.redemption_requests where id=any(p_order_ids);
 if v_count<>v_expected or (select count(distinct user_id) from public.redemption_requests where id=any(p_order_ids))<>1 then
  raise exception 'Every selected order must exist and belong to one customer.';
 end if;
 if exists(select 1 from public.redemption_requests where id=any(p_order_ids)
  and (delivery_id is not null or status not in ('pending','reviewing','ordered','trade_locked','ready_to_trade'))) then
  raise exception 'Only ungrouped, unsent orders can be added to a new delivery.';
 end if;
 insert into public.sq_deliveries(user_id,label,created_by)
 values(v_user,coalesce(nullif(trim(p_label),''),'Steam delivery'),auth.uid()) returning id into v_id;
 update public.redemption_requests set delivery_id=v_id,updated_at=now() where id=any(p_order_ids);
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'delivery_created','delivery',v_id::text,jsonb_build_object('orders',p_order_ids,'user_id',v_user));
 return jsonb_build_object('ok',true,'delivery_id',v_id,'count',v_count);
end $$;
revoke all on function public.sq_admin_create_delivery(bigint[],text) from public,anon;
grant execute on function public.sq_admin_create_delivery(bigint[],text) to authenticated;

create or replace function public.sq_admin_delivery_orders(p_limit integer default 100,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(t)) from
  (select r.*,p.username,p.steam_name,p.contact_email,p.steam_trade_url as current_trade_url,
    (r.status<>'trade_sent' and r.steam_trade_url is distinct from p.steam_trade_url) as trade_url_needs_review,
    d.label as delivery_label
   from public.redemption_requests r left join public.profiles p on p.id=r.user_id
    left join public.sq_deliveries d on d.id=r.delivery_id
   where r.status not in ('completed','rejected','refunded','cancelled')
   order by r.user_id,r.delivery_id nulls last,r.created_at,r.id
   limit greatest(1,least(coalesce(p_limit,100),1000)) offset greatest(0,coalesce(p_offset,0))) t),'[]'::jsonb),
  'total',(select count(*) from public.redemption_requests where status not in ('completed','rejected','refunded','cancelled')));
end $$;
revoke all on function public.sq_admin_delivery_orders(integer,integer) from public,anon;
grant execute on function public.sq_admin_delivery_orders(integer,integer) to authenticated;

create or replace function public.sq_admin_delivery_update(
 p_delivery_id uuid,p_status text,p_lock_until timestamptz default null,p_trade_offer_url text default null,p_note text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.redemption_requests%rowtype; n int:=0; v_lock timestamptz;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if p_status not in ('reviewing','ordered','trade_locked','ready_to_trade','trade_sent','completed') then
  raise exception 'Unsupported delivery action. Refunds are handled on individual orders.';
 end if;
 if length(coalesce(p_note,''))>2000 then raise exception 'Customer update too long.'; end if;
 -- Every group action is one transaction: a failed item rolls the whole group back.
 perform p.id from public.profiles p join public.sq_deliveries d on d.user_id=p.id
  where d.id=p_delivery_id for update of p;
 perform id from public.sq_deliveries where id=p_delivery_id for update;
 if not found then raise exception 'Delivery not found.'; end if;
 v_lock:=coalesce(p_lock_until,now()+interval '192 hours');
 for r in select * from public.redemption_requests where delivery_id=p_delivery_id
  and status not in ('completed','rejected','refunded','cancelled') order by id for update loop
  if p_status='trade_locked' and r.status in ('pending','reviewing') and r.fulfillment_mode='orderable' then
   perform public.sq_admin_update_order(r.id,'ordered',r.admin_note,null,null);
  end if;
  perform public.sq_admin_update_order(r.id,p_status,r.admin_note,p_trade_offer_url,
   case when p_status='trade_locked' then v_lock else null end);
  if p_note is not null then perform public.sq_admin_order_customer_note(r.id,p_note); end if;
  n:=n+1;
 end loop;
 if n=0 then raise exception 'No active orders in this delivery.'; end if;
 return jsonb_build_object('ok',true,'count',n,'lock_until',case when p_status='trade_locked' then v_lock end);
end $$;
revoke all on function public.sq_admin_delivery_update(uuid,text,timestamptz,text,text) from public,anon;
grant execute on function public.sq_admin_delivery_update(uuid,text,timestamptz,text,text) to authenticated;

create or replace function public.sq_admin_review_delivery_trade_url(p_delivery_id uuid,p_expected_url text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; n int:=0;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 perform p.id from public.profiles p join public.sq_deliveries d on d.user_id=p.id
  where d.id=p_delivery_id for update of p;
 for r in select id from public.redemption_requests where delivery_id=p_delivery_id
  and status in ('pending','reviewing','ordered','trade_locked','ready_to_trade') order by id loop
  perform public.sq_admin_review_trade_url(r.id,p_expected_url);n:=n+1;
 end loop;
 if n=0 then raise exception 'No unsent orders in this delivery.'; end if;
 return jsonb_build_object('ok',true,'count',n);
end $$;
revoke all on function public.sq_admin_review_delivery_trade_url(uuid,text) from public,anon;
grant execute on function public.sq_admin_review_delivery_trade_url(uuid,text) to authenticated;

create or replace function public.sq_my_orders(p_status text default 'active',p_limit integer default 25,p_offset integer default 0)
returns jsonb language sql stable security definer set search_path=public as $$
 with mine as (select r.id,r.order_number,r.reward_id,r.reward_name,r.points_coins,r.points_cost,r.status,r.fulfillment_mode,
  r.created_at,r.updated_at,r.trade_locked_until,r.estimated_ready_at,r.trade_offer_url,r.customer_note,r.delivery_id,
  d.label as delivery_label,(r.status<>'trade_sent' and r.steam_trade_url is distinct from p.steam_trade_url) as trade_url_needs_review
  from public.redemption_requests r left join public.sq_deliveries d on d.id=r.delivery_id
   left join public.profiles p on p.id=r.user_id where r.user_id=auth.uid()),
 filtered as (select * from mine where p_status='all' or
  (p_status='active' and status not in ('completed','cancelled','refunded','rejected')) or
  (p_status='closed' and status in ('completed','cancelled','refunded','rejected'))),
 page as (select * from filtered order by created_at desc,id desc
  limit greatest(1,least(coalesce(p_limit,25),100)) offset greatest(0,coalesce(p_offset,0)))
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc,p.id desc) from page p),'[]'::jsonb),
  'total',(select count(*) from filtered),'active',(select count(*) from mine where status not in ('completed','cancelled','refunded','rejected')),
  'locked',(select count(*) from mine where status='trade_locked'),
  'sent',(select count(*) from mine where status='trade_sent'));
$$;
revoke all on function public.sq_my_orders(text,integer,integer) from public,anon;
grant execute on function public.sq_my_orders(text,integer,integer) to authenticated;

create or replace function public.sq_my_order(p_order_id bigint)
returns jsonb language sql stable security definer set search_path=public as $$
 select to_jsonb(t) from (select r.id,r.order_number,r.reward_id,r.reward_name,r.points_coins,r.points_cost,r.status,
  r.fulfillment_mode,r.estimated_ready_at,r.purchased_at,r.trade_locked_until,r.trade_sent_at,r.ready_at,r.completed_at,r.refunded_at,
  r.created_at,r.updated_at,r.trade_offer_url,r.customer_note,r.delivery_id,d.label as delivery_label,
  (r.status in ('pending','reviewing','ordered','trade_locked','ready_to_trade') and
   r.steam_trade_url is distinct from p.steam_trade_url) as trade_url_needs_review,
  coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'order_number',s.order_number,'reward_name',s.reward_name,
   'coins',s.points_coins,'status',s.status) order by s.id) from public.redemption_requests s
   where s.delivery_id=r.delivery_id and s.user_id=auth.uid()),'[]'::jsonb) as delivery_items
  from public.redemption_requests r left join public.sq_deliveries d on d.id=r.delivery_id
   left join public.profiles p on p.id=r.user_id where r.id=p_order_id and r.user_id=auth.uid()) t;
$$;

-- Normalize provider evidence without making up money from coin balances.
create or replace function public.sq_earning_records()
returns table(record_key text,user_id uuid,source text,coins bigint,status text,revenue_usd numeric,occurred_at timestamptz)
language sql stable security definer set search_path=public as $$
 with events as (select e.*,
  case when lower(provider) in ('cpx','cpx-research','cpx_research') then 'cpx'
   when lower(provider)='timewall' then case when raw_payload->>'earning_source'='timewall_earn' then 'timewall_earn' else 'timewall_surveys' end
   else lower(provider) end as src
  from public.offerwall_events e),
 legacy as (select c.*,
  case when lower(coalesce(metadata->>'provider','')) in ('cpx','cpx-research','cpx_research')
    or lower(coalesce(source_id,'')) like 'cpx:%' or coalesce(reason,'') ~* '(^|[^a-z])cpx([^a-z]|$)' then 'cpx'
   when lower(coalesce(metadata->>'provider',''))='timewall' or lower(coalesce(source_id,'')) like 'timewall:%'
    then case when metadata->>'earning_source'='timewall_earn' then 'timewall_earn' else 'timewall_surveys' end
   else null end as src
  from public.coin_adjustments c where amount>0)
 select 'event:'||e.id,e.user_id,e.src,e.amount::bigint,lower(e.status),
  case when coalesce(e.raw_payload->>'revenue_usd',e.raw_payload->>'amount_usd',case when e.provider='timewall' then e.raw_payload->>'revenue' end,'')
   ~ '^-?[0-9]{1,9}(\.[0-9]{1,8})?$' then
   coalesce(e.raw_payload->>'revenue_usd',e.raw_payload->>'amount_usd',case when e.provider='timewall' then e.raw_payload->>'revenue' end)::numeric else null end,
  e.created_at from events e where e.src in ('cpx','timewall_surveys','timewall_earn')
 union all
 select 'ledger:'||c.id,c.user_id,c.src,c.amount::bigint,
  case when exists(select 1 from public.coin_adjustments n where n.user_id=c.user_id and n.amount<0
   and n.source_id=c.source_id and c.source_id is not null and n.source_type='offerwall_reversal') then 'reversed' else 'completed' end,
  null::numeric,c.created_at from legacy c where c.src is not null
   and not exists(select 1 from events e where e.user_id=c.user_id and (e.src=c.src or (e.provider='timewall' and c.src like 'timewall_%')) and
    (c.source_id=e.provider||':'||e.provider_event_id or c.source_id=e.provider_event_id or c.metadata->>'event_id'=e.provider_event_id));
$$;
revoke all on function public.sq_earning_records() from public,anon,authenticated;

create or replace function public.sq_record_earning_activity(p_source text,p_kind text,p_launch_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then return false; end if;
 if p_source not in ('cpx','timewall_surveys','timewall_earn') or p_kind not in ('view','open') or p_launch_id is null then
  raise exception 'Invalid earning activity.';
 end if;
 -- Analytics is untrusted engagement evidence, NEVER permission to award coins.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_source||p_kind,15000));
 if exists(select 1 from public.sq_product_events where user_id=auth.uid() and event_name='earning_'||p_kind
  and properties->>'source'=p_source and
  (properties->>'launch_id'=p_launch_id::text or created_at>now()-interval '5 seconds')) then return false; end if;
 return public.sq_track_event('earning_'||p_kind,'/'||case when p_source='timewall_earn' then 'earn' else 'surveys' end,
  jsonb_build_object('source',p_source,'launch_id',p_launch_id));
end $$;
revoke all on function public.sq_record_earning_activity(text,text,uuid) from public,anon;
grant execute on function public.sq_record_earning_activity(text,text,uuid) to authenticated;

create or replace function public.sq_admin_user_earnings(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('source',s.source,
  'verified_rewards',(select count(*) from public.sq_earning_records() e where e.user_id=p_user_id and e.source=s.source and e.status='completed'),
  'coins',(select coalesce(sum(coins),0) from public.sq_earning_records() e where e.user_id=p_user_id and e.source=s.source and e.status='completed'),
  'reversed',(select count(*) from public.sq_earning_records() e where e.user_id=p_user_id and e.source=s.source and e.status in ('reversed','rejected')),
  'opens',(select count(*) from public.sq_product_events e where e.user_id=p_user_id and
   ((e.event_name='earning_open' and e.properties->>'source'=s.source) or (s.source='cpx' and e.event_name='cpx_wall_open_requested'))),
  'views',(select count(*) from public.sq_product_events e where e.user_id=p_user_id and e.event_name='earning_view' and e.properties->>'source'=s.source))), '[]'::jsonb)
 into result from (values('cpx'),('timewall_surveys'),('timewall_earn')) s(source);
 return result;
end $$;
revoke all on function public.sq_admin_user_earnings(uuid) from public,anon;
grant execute on function public.sq_admin_user_earnings(uuid) to authenticated;

create or replace function public.sq_admin_cpx_activity(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare m jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 select value into m from jsonb_array_elements(public.sq_admin_user_earnings(p_user_id)) where value->>'source'='cpx';
 return jsonb_build_object('completed_reward_events',(m->>'verified_rewards')::bigint,
  'postback_rows',(select count(*) from public.offerwall_events where user_id=p_user_id and lower(provider) in ('cpx','cpx-research','cpx_research')),
  'ledger_credit_rows',(m->>'verified_rewards')::bigint,'logged_opens',(m->>'opens')::bigint,
  'verified_coins',(m->>'coins')::bigint,'views',(m->>'views')::bigint,
  'note','Verified rewards include provider-approved screen-out compensation. Openings count observed launch controls, not every survey inside a cross-origin iframe. Old untracked openings cannot be reconstructed. Legacy CPX-labelled coin credits are included without inventing USD revenue.');
end $$;

create or replace function public.sq_owner_earning_stats(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare since timestamptz; sources jsonb; totals jsonb;
begin
 if not public.is_owner() then raise exception 'Owner access required.'; end if;
 if p_days not in (0,7,30,90) then raise exception 'Invalid period.'; end if;
 since:=case when p_days=0 then '-infinity'::timestamptz else now()-make_interval(days=>p_days) end;
 with sources_list as (select * from (values('cpx'),('timewall_surveys'),('timewall_earn')) s(source)),
 records as (select * from public.sq_earning_records() where occurred_at>=since),
 metrics as (select s.source,
  (select count(*) from public.sq_product_events p where p.created_at>=since and
   ((p.event_name='earning_open' and p.properties->>'source'=s.source) or (s.source='cpx' and p.event_name='cpx_wall_open_requested'))) as opens,
  (select count(*) from public.sq_product_events p where p.created_at>=since and p.event_name='earning_view' and p.properties->>'source'=s.source) as views,
  (select count(*) from records e where e.source=s.source and status='completed') as verified_rewards,
  (select count(distinct user_id) from records e where e.source=s.source and status='completed') as completing_users,
  (select count(*) from records e where e.source=s.source and status in ('reversed','rejected')) as reversed,
  (select count(*) from records e where e.source=s.source and status='pending') as pending,
  (select coalesce(sum(coins),0) from records e where e.source=s.source and status='completed') as coins,
  (select sum(revenue_usd) from records e where e.source=s.source and status='completed') as reported_revenue_usd,
  (select count(*) from records e where e.source=s.source and status='completed' and revenue_usd is null) as revenue_unknown
 from sources_list s)
 select jsonb_agg(to_jsonb(m) order by source),jsonb_build_object('opens',sum(opens),'views',sum(views),
  'verified_rewards',sum(verified_rewards),'coins',sum(coins),'reversed',sum(reversed),'pending',sum(pending),
  'reported_revenue_usd',sum(reported_revenue_usd),'revenue_unknown',sum(revenue_unknown),
  'completing_users',(select count(distinct user_id) from records where status='completed'))
 into sources,totals from metrics m;
 return jsonb_build_object('sources',sources,'totals',totals,'days',p_days,'currency','USD',
  'daily',coalesce((select jsonb_agg(to_jsonb(d) order by day desc) from
   (select occurred_at::date as day,source,count(*) filter(where status='completed') as verified_rewards,
    sum(revenue_usd) filter(where status='completed') as reported_revenue_usd
    from public.sq_earning_records() where occurred_at>=greatest(since,now()-interval '90 days')
    group by 1,2 order by 1 desc,2 limit 270) d),'[]'::jsonb),
  'note','Reported USD is callback revenue, not money received or profit. Missing revenue remains unknown. Use Finance for actual settlements. Opens are observed launch controls; views are provider displays. No historical iframe clicks are fabricated.');
end $$;
revoke all on function public.sq_owner_earning_stats(integer) from public,anon;
grant execute on function public.sq_owner_earning_stats(integer) to authenticated;

-- TimeWall credit entry with server-selected placement attribution.
create or replace function public.sq_process_timewall_postback_v15(
 p_event_id text,p_user_id uuid,p_amount integer,p_revenue text,p_source text default 'timewall_surveys'
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare e public.offerwall_events%rowtype;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required.'; end if;
 if p_source not in ('timewall_surveys','timewall_earn') or p_amount is null or p_amount<1 or p_amount>5000
 or p_revenue is null or p_revenue !~ '^[0-9]{1,6}(\.[0-9]{1,6})?$' then raise exception 'Invalid TimeWall reward.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,10452));
 select * into e from public.offerwall_events where provider='timewall' and provider_event_id=p_event_id;
 if found and (e.user_id is distinct from p_user_id or e.amount is distinct from p_amount) then raise exception 'Event identity mismatch.'; end if;
 if found and e.status in ('reversed','rejected') then return jsonb_build_object('ok',true,'status','ignored_terminal'); end if;
 if found and e.raw_payload->>'earning_source' is not null and e.raw_payload->>'earning_source'<>p_source then
  raise exception 'Placement attribution mismatch.';
 end if;
 if e.id is null and coalesce((select sum(amount) from public.offerwall_events
  where provider='timewall' and user_id=p_user_id and created_at>now()-interval '24 hours'),0)+p_amount>15000 then
  raise exception 'TimeWall daily limit exceeded.';
 end if;
 return public.process_offerwall_postback('timewall',p_event_id,p_user_id,p_amount,'completed',
  jsonb_build_object('revenue_usd',p_revenue,'earning_source',p_source,'coins',p_amount));
end $$;
revoke all on function public.sq_process_timewall_postback_v15(text,uuid,integer,text,text) from public,anon,authenticated;
grant execute on function public.sq_process_timewall_postback_v15(text,uuid,integer,text,text) to service_role;
create or replace function public.sq_process_timewall_postback(p_event_id text,p_user_id uuid,p_amount integer,p_revenue text)
returns jsonb language sql security definer set search_path=public as $$
 select public.sq_process_timewall_postback_v15(p_event_id,p_user_id,p_amount,p_revenue,'timewall_surveys');
$$;

-- Function replacements for existing order and postback entry points follow.
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
    'action', 'open', 'all', 'pending', 'reviewing', 'ordered', 'trade_locked',
    'ready_to_trade', 'trade_sent', 'completed', 'rejected', 'refunded', 'cancelled'
  ) then
    raise exception 'Invalid order status filter.';
  end if;

  return query
  select r.*
  from public.redemption_requests r
  where (
    v_status = 'all' or
    (v_status = 'action' and
      (r.status in ('pending','reviewing','ordered','ready_to_trade') or
       (r.status='trade_locked' and (r.trade_locked_until<=now() or r.steam_trade_url is distinct from
        (select steam_trade_url from public.profiles where id=r.user_id))))) or
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
create or replace function public.sq_my_coin_history(p_kind text default 'all',p_limit integer default 25,p_offset integer default 0)
returns jsonb language sql stable security definer set search_path=public as $$
 with records as (
  select c.id,c.amount,c.reason,c.source_type,c.source_id,c.created_at,
   case when c.source_type='redemption_refund' then 'refund'
    when c.source_type in ('reward_order','redemption_hold','redemption') then 'reward'
    when c.source_type in ('offerwall_credit','offerwall_reversal') or lower(coalesce(c.source_type,'')) like '%cpx%'
      or c.reason ~* '(^|[^a-z])cpx([^a-z]|$)' or lower(coalesce(c.metadata->>'provider','')) in ('cpx','cpx-research','cpx_research')
      then case when c.metadata->>'earning_source'='timewall_earn' then 'earn' else 'survey' end
    when c.source_type in ('promo_code','promo_redemption') or c.reason like 'Promo code: %' then 'promo'
    when c.source_type in ('level_bonus','level_up_bonus','level_reward') then 'level' else 'adjustment' end as kind,
   (select r.id from public.redemption_requests r where r.user_id=auth.uid() and r.id::text=c.source_id
    and c.source_type in ('reward_order','redemption_hold','redemption','redemption_refund') limit 1) as order_id,
   case when c.source_type in ('offerwall_credit','offerwall_reversal') then case when c.metadata->>'provider'='timewall' then
    case when c.metadata->>'earning_source'='timewall_earn' then 'TimeWall Earn' else 'TimeWall Surveys' end
    else left(coalesce(c.metadata->>'provider','Partner'),50) end else
    case when c.reason ~* '(^|[^a-z])cpx([^a-z]|$)' then 'CPX' else null end end as provider
  from public.coin_adjustments c where c.user_id=auth.uid()
 ), filtered as (select * from records where p_kind='all' or kind=p_kind), page as (
  select * from filtered order by created_at desc,id desc limit greatest(1,least(coalesce(p_limit,25),100)) offset greatest(0,coalesce(p_offset,0)))
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc,p.id desc) from page p),'[]'::jsonb),
  'total',(select count(*) from filtered));
$$;
revoke all on function public.sq_my_coin_history(text,integer,integer) from public,anon;
grant execute on function public.sq_my_coin_history(text,integer,integer) to authenticated;
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

  -- Consistent lock order prevents a trade-URL change racing a sent status.
  perform p.id from public.profiles p join public.redemption_requests r on r.user_id=p.id
   where r.id=p_request_id for update of p;
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
    if v_trade_locked_until is null then v_trade_locked_until := now()+interval '192 hours'; end if;
    if v_trade_locked_until <= now() then
      raise exception 'Trade-lock end time must be in the future. Use Ready to trade only after the lock has ended.';
    end if;
  end if;

  if v_status = 'ready_to_trade' and v_old_status='trade_locked'
    and v_request.trade_locked_until>now() then
    raise exception 'The recorded Steam trade lock has not ended.';
  end if;
  if v_status = 'trade_sent' and v_old_status<>'trade_sent' and
    v_request.steam_trade_url is distinct from
      (select steam_trade_url from public.profiles where id=v_request.user_id) then
    raise exception 'Trade URL changed. Review the current customer link before marking sent.';
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
      trade_sent_at = case when v_status = 'trade_sent' then coalesce(trade_sent_at,now()) else trade_sent_at end,
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

create or replace function public.process_offerwall_postback(
  p_provider text,
  p_event_id text,
  p_user_id uuid,
  p_amount integer,
  p_status text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.offerwall_events%rowtype;
  v_previous text;
  v_balance integer;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required.'; end if;
  p_provider := lower(trim(p_provider));
  p_status := lower(trim(p_status));
  if p_provider not in ('cpx', 'bitlabs', 'lootably', 'timewall') then raise exception 'Unsupported provider.'; end if;
  if p_event_id is null or char_length(p_event_id) > 180 then raise exception 'Invalid event id.'; end if;
  if p_amount < 0 or p_amount > 100000 then raise exception 'Invalid coin amount.'; end if;
  if p_status not in ('pending', 'completed', 'reversed', 'rejected') then raise exception 'Invalid status.'; end if;

  perform 1 from auth.users where id = p_user_id;
  if not found then raise exception 'Unknown user.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_provider||':'||p_event_id,15001));
  select * into v_event from public.offerwall_events
  where provider = p_provider and provider_event_id = p_event_id for update;
  if not found then
    insert into public.offerwall_events(provider, provider_event_id, user_id, amount, status, raw_payload, processed_at)
    values (p_provider, p_event_id, p_user_id, p_amount, 'pending', coalesce(p_payload, '{}'::jsonb), now())
    returning * into v_event;
  elsif v_event.user_id is distinct from p_user_id or v_event.amount is distinct from p_amount then
    raise exception 'Postback does not match the original event.';
  end if;

  v_previous := v_event.status;
  if v_previous in ('reversed','rejected') or
     (v_previous='completed' and p_status='pending') then
    return jsonb_build_object('ok',true,'event_id',v_event.id,'status',v_previous,'ignored',true);
  end if;
  if p_status = 'completed' and v_previous <> 'completed' then
    insert into public.profiles(id, username) values (p_user_id, 'user') on conflict (id) do nothing;
    update public.profiles set points_balance = coalesce(points_balance, 0) + p_amount where id = p_user_id;
    insert into public.coin_adjustments(user_id, amount, reason, source_type, source_id, metadata)
    values (p_user_id, p_amount, initcap(p_provider) || case when coalesce(p_payload->>'earning_source',v_event.raw_payload->>'earning_source')='timewall_earn' then ' task completion' else ' survey completion' end, 'offerwall_credit', p_provider || ':' || p_event_id, jsonb_build_object('provider', p_provider, 'earning_source',coalesce(p_payload->>'earning_source',v_event.raw_payload->>'earning_source')));
  elsif p_status in ('reversed', 'rejected') and v_previous = 'completed' then
    select coalesce(points_balance, 0) into v_balance from public.profiles where id = p_user_id for update;
    update public.profiles
      set points_balance = greatest(0, coalesce(points_balance, 0) - p_amount),
          account_status = case when coalesce(v_balance, 0) < p_amount then 'under_review' else account_status end
      where id = p_user_id;
    insert into public.coin_adjustments(user_id, amount, reason, source_type, source_id, metadata)
    values (p_user_id, -p_amount, initcap(p_provider) || case when coalesce(p_payload->>'earning_source',v_event.raw_payload->>'earning_source')='timewall_earn' then ' task reversal' else ' survey reversal' end, 'offerwall_reversal', p_provider || ':' || p_event_id, jsonb_build_object('provider', p_provider, 'earning_source',coalesce(p_payload->>'earning_source',v_event.raw_payload->>'earning_source')));
  end if;

  update public.offerwall_events set status = p_status, raw_payload = coalesce(raw_payload,'{}'::jsonb)||coalesce(p_payload,'{}'::jsonb), processed_at = now()
  where id = v_event.id;
  return jsonb_build_object('ok', true, 'event_id', v_event.id, 'previous_status', v_previous, 'status', p_status);
end;
$$;

revoke all on function public.process_offerwall_postback(text, text, uuid, integer, text, jsonb) from public, anon, authenticated;
grant execute on function public.process_offerwall_postback(text, text, uuid, integer, text, jsonb) to service_role;

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
    'actionable_rewards', (select count(*) from public.redemption_requests r left join public.profiles p on p.id=r.user_id
      where r.status in ('pending','reviewing','ordered','ready_to_trade')
       or (r.status='trade_locked' and (r.trade_locked_until<=now() or r.steam_trade_url is distinct from p.steam_trade_url))),
    'locked_rewards', (select count(*) from public.redemption_requests where status='trade_locked' and trade_locked_until>now()),
    'completed_rewards', v_completed_rewards,
    'open_support', v_open_support,
    'coin_liability', v_coin_liability,
    'positive_coin_credits_24h', v_earned_24h
  );
end;
$$;

commit;
notify pgrst,'reload schema';
