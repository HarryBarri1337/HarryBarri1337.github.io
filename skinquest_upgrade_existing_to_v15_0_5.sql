-- SkinQuest v15.0.5 finance refinement (apply to an existing v15.0.5/v15.0.4 database).
-- This keeps the release version at v15.0.5 while replacing the earlier Finance & Funding model.
-- Finance is now actual-cash-only, SEK-first, admin-readable, creator-attributed and editable/deletable with server-side permissions.

begin;

alter table public.sq_finance_entries add column if not exists external_order_id text;
alter table public.sq_finance_entries add column if not exists updated_by uuid references auth.users(id) on delete set null;
alter table public.sq_finance_entries add column if not exists updated_at timestamptz not null default now();
alter table public.sq_finance_entries alter column currency set default 'SEK';
alter table public.sq_finance_entries alter column settlement set default 'paid';
alter table public.sq_finance_entries drop constraint if exists sq_finance_entries_currency_check;
alter table public.sq_finance_entries add constraint sq_finance_entries_currency_check check(currency in ('SEK','EUR'));
alter table public.sq_finance_entries drop constraint if exists sq_finance_entries_category_check;
drop index if exists public.sq_finance_reference_idx;

drop policy if exists "sq finance owner read" on public.sq_finance_entries;
drop policy if exists "sq finance admin read" on public.sq_finance_entries;
create policy "sq finance admin read" on public.sq_finance_entries for select to authenticated using(public.is_admin());
revoke all on public.sq_finance_entries from anon,authenticated;
grant select on public.sq_finance_entries to authenticated;

-- Existing EUR records are deliberately preserved as EUR and excluded from the new SEK cash total.
-- Re-enter or edit them in Finance if you want them represented as SEK; the migration never invents an exchange rate.

create or replace function public.sq_admin_finance_save(
 p_id uuid,p_kind text,p_category text,p_amount_minor bigint,p_occurred_on date,
 p_reference text,p_external_order_id text default null,p_order_id bigint default null,p_note text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_entry public.sq_finance_entries%rowtype; v_number text; v_existing boolean := false;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if p_id is null then raise exception 'An entry identifier is required.'; end if;
 if p_kind not in ('income','expense','funding') then raise exception 'Choose a valid finance type.'; end if;
 if p_kind='funding' and not public.is_owner() then raise exception 'Only an owner can record owner funding.'; end if;
 if p_category not in ('provider','item_purchase','hosting','marketing','fees','other') then raise exception 'Choose a valid finance category.'; end if;
 if p_kind='income' and p_category not in ('provider','other') then raise exception 'Choose an income category.'; end if;
 if p_kind='expense' and p_category not in ('item_purchase','hosting','marketing','fees','other') then raise exception 'Choose an expense category.'; end if;
 if p_kind='funding' and p_category<>'other' then raise exception 'Owner funding uses the Other category.'; end if;
 if p_amount_minor is null or p_amount_minor not between 1 and 100000000000 then raise exception 'Enter a positive SEK amount.'; end if;
 if p_occurred_on is null or p_occurred_on>current_date+365 then raise exception 'Choose a valid entry date.'; end if;
 if length(trim(coalesce(p_reference,''))) not between 1 and 120 or length(coalesce(p_note,''))>1000 or length(coalesce(p_external_order_id,''))>120 then raise exception 'Check the reference, order ID and note lengths.'; end if;
 if p_order_id is not null then
  if p_kind<>'expense' or p_category<>'item_purchase' then raise exception 'Only reward purchases can be linked to a SkinQuest order.'; end if;
  select order_number into v_number from public.redemption_requests where id=p_order_id;
  if not found then raise exception 'SkinQuest order not found.'; end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('sq-finance-'||p_id::text,0));
 select * into v_entry from public.sq_finance_entries where id=p_id for update;
 v_existing := found;
 if v_existing and not (public.is_owner() or v_entry.created_by=auth.uid()) then raise exception 'You can only edit finance records you created.'; end if;
 if v_existing then
  update public.sq_finance_entries set kind=p_kind,category=p_category,amount_minor=p_amount_minor,currency='SEK',settlement='paid',occurred_on=p_occurred_on,
   reference=trim(p_reference),external_order_id=nullif(left(trim(p_external_order_id),120),''),provider=null,order_id=p_order_id,order_snapshot=v_number,
   note=nullif(trim(p_note),''),updated_by=auth.uid(),updated_at=now(),settled_at=coalesce(settled_at,now()),voided_at=null,voided_by=null,void_reason=null
  where id=p_id returning * into v_entry;
 else
  insert into public.sq_finance_entries(id,kind,category,amount_minor,currency,settlement,occurred_on,reference,external_order_id,provider,order_id,order_snapshot,note,created_by,updated_by,settled_at)
  values(p_id,p_kind,p_category,p_amount_minor,'SEK','paid',p_occurred_on,trim(p_reference),nullif(left(trim(p_external_order_id),120),''),null,p_order_id,v_number,nullif(trim(p_note),''),auth.uid(),auth.uid(),now()) returning * into v_entry;
 end if;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),case when v_existing then 'finance_edit' else 'finance_record' end,'finance',p_id::text,jsonb_build_object('kind',p_kind,'amount_minor',p_amount_minor,'currency','SEK','reference',trim(p_reference),'external_order_id',p_external_order_id));
 return to_jsonb(v_entry);
end;
$$;
revoke all on function public.sq_admin_finance_save(uuid,text,text,bigint,date,text,text,bigint,text) from public,anon;
grant execute on function public.sq_admin_finance_save(uuid,text,text,bigint,date,text,text,bigint,text) to authenticated;

create or replace function public.sq_admin_finance_delete(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_entry public.sq_finance_entries%rowtype;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 select * into v_entry from public.sq_finance_entries where id=p_id for update;
 if not found then raise exception 'Finance record not found.'; end if;
 if not (public.is_owner() or v_entry.created_by=auth.uid()) then raise exception 'You can only delete finance records you created.'; end if;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'finance_delete','finance',p_id::text,jsonb_build_object('kind',v_entry.kind,'category',v_entry.category,'amount_minor',v_entry.amount_minor,'currency',v_entry.currency,'reference',v_entry.reference,'external_order_id',v_entry.external_order_id,'created_by',v_entry.created_by));
 delete from public.sq_finance_entries where id=p_id;
 return jsonb_build_object('deleted',true,'id',p_id);
end;
$$;
revoke all on function public.sq_admin_finance_delete(uuid) from public,anon;
grant execute on function public.sq_admin_finance_delete(uuid) to authenticated;

create or replace function public.sq_admin_finance_dashboard(p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 with live as (select * from public.sq_finance_entries where voided_at is null and currency='SEK'), totals as (
  select coalesce(sum(amount_minor) filter(where kind='income'),0) as income,
   coalesce(sum(amount_minor) filter(where kind='expense'),0) as expenses,
   coalesce(sum(amount_minor) filter(where kind='funding'),0) as funding,count(*) as recorded_count from live
 ), costs as (
  select order_id,sum(amount_minor) as amount from live where kind='expense' and category='item_purchase' and order_id is not null group by order_id
 ), open_orders as (
  select r.id,r.order_number,r.reward_name,r.points_coins,r.status,r.fulfillment_mode,c.amount as recorded_purchase_minor,
   null::bigint as current_steam_estimate_minor
  from public.redemption_requests r left join public.reward_items i on i.id=r.reward_id left join costs c on c.order_id=r.id
  where r.status not in ('completed','rejected','refunded','cancelled')
 ), page as (select * from public.sq_finance_entries where voided_at is null order by occurred_on desc,created_at desc,id limit greatest(1,least(coalesce(p_limit,50),100)) offset greatest(0,coalesce(p_offset,0)))
 select jsonb_build_object('currency','SEK','totals',(select to_jsonb(t) from totals t),
  'entries',coalesce((select jsonb_agg(to_jsonb(e) order by occurred_on desc,created_at desc,id) from page e),'[]'::jsonb),
  'total',(select count(*) from public.sq_finance_entries where voided_at is null),
  'legacy_currency_count',(select count(*) from public.sq_finance_entries where voided_at is null and currency<>'SEK'),
  'customer_coin_balance',(select coalesce(sum(p.points_balance),0) from public.profiles p where not exists(select 1 from public.admin_users a where a.user_id=p.id)),
  'open_orders',coalesce((select jsonb_agg(to_jsonb(o) order by o.id desc) from (select * from open_orders order by id desc limit 100) o),'[]'::jsonb),
  'open_order_count',(select count(*) from open_orders),
  'unrecorded_purchase_count',(select count(*) from open_orders where recorded_purchase_minor is null),
  'unknown_estimate_count',(select count(*) from open_orders where recorded_purchase_minor is null and current_steam_estimate_minor is null),
  'unrecorded_steam_estimate_minor',(select coalesce(sum(current_steam_estimate_minor),0) from open_orders where recorded_purchase_minor is null)) into v_result;
 return v_result;
end;
$$;
revoke all on function public.sq_admin_finance_dashboard(integer,integer) from public,anon;
grant execute on function public.sq_admin_finance_dashboard(integer,integer) to authenticated;

create or replace function public.sq_owner_finance_dashboard(p_limit integer default 50,p_offset integer default 0)
returns jsonb language sql stable security definer set search_path=public as $$ select public.sq_admin_finance_dashboard(p_limit,p_offset); $$;
revoke all on function public.sq_owner_finance_dashboard(integer,integer) from public,anon;
grant execute on function public.sq_owner_finance_dashboard(integer,integer) to authenticated;

commit;
notify pgrst,'reload schema';
