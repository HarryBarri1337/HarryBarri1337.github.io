-- SkinQuest v14.5.3 -> v14.5.4. Back up first; run only this upgrade.
begin;
lock table public.reward_items, public.redemption_requests in share row exclusive mode;

-- Normalize the legacy link without deleting orders or changing coin snapshots.
do $$
declare c record; v_conflict boolean;
begin
  if exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='redemption_requests' and column_name='reward_item_id') then
    execute 'select exists(select 1 from public.redemption_requests where reward_id is not null
      and reward_item_id is not null and reward_id<>reward_item_id)' into v_conflict;
    if v_conflict then raise exception 'Conflicting legacy reward links. No changes applied; inspect the affected orders first.'; end if;
    execute 'update public.redemption_requests set reward_id=reward_item_id
      where reward_id is null and reward_item_id is not null';
  end if;
  for c in
    select con.conname, a.attname
    from pg_constraint con
    join pg_attribute a on a.attrelid=con.conrelid and a.attnum=con.conkey[1]
    join pg_attribute b on b.attrelid=con.confrelid and b.attnum=con.confkey[1]
    where con.contype='f' and con.conrelid='public.redemption_requests'::regclass
      and con.confrelid='public.reward_items'::regclass
      and cardinality(con.conkey)=1 and cardinality(con.confkey)=1
      and a.attname in ('reward_id','reward_item_id') and b.attname='id'
  loop
    execute format('alter table public.redemption_requests alter column %I drop not null',c.attname);
    execute format('alter table public.redemption_requests drop constraint %I',c.conname);
    execute format('alter table public.redemption_requests add constraint %I foreign key (%I) references public.reward_items(id) on delete set null',c.conname,c.attname);
  end loop;
end;
$$;

-- A separate RPC preserves compatibility with existing global user search.
create or replace function public.sq_admin_filter_users(
 p_query text default null,p_role text default 'all',p_login text default 'all',
 p_sort text default 'newest',p_limit integer default 75,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare
 v_query text:=left(trim(coalesce(p_query,'')),120);
 v_role text:=coalesce(p_role,'all');
 v_login text:=coalesce(p_login,'all');
 v_sort text:=coalesce(p_sort,'newest');
 v_limit integer:=greatest(1,least(coalesce(p_limit,75),200));
 v_offset integer:=greatest(0,coalesce(p_offset,0));
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if v_role not in ('all','user','staff','admin','owner') then v_role:='all'; end if;
 if v_login not in ('all','steam','other') then v_login:='all'; end if;
 if v_sort not in ('newest','oldest','coins-desc','coins-asc','role','name') then v_sort:='newest'; end if;
 return (
 with base as (
 select p.id as user_id,
 case when coalesce(u.email,'') ilike '%@steam.skinquestcs.com' then null else u.email::text end as email,
 p.username,p.steam_name,p.steam_id,
 case when p.contact_email_verified_at is not null then p.contact_email else null end as contact_email,
 p.contact_email_verified_at,coalesce(p.points_balance,0) as points_balance,
 coalesce(p.account_status,'active') as account_status,p.created_at,
 coalesce(au.role,'user') as role,
 (coalesce(u.email,'') ilike '%@steam.skinquestcs.com'
  or coalesce(u.raw_app_meta_data->>'provider','')='steam'
  or coalesce(u.raw_app_meta_data->'providers','[]'::jsonb) ? 'steam'
  or exists(select 1 from auth.identities i where i.user_id=p.id and i.provider='steam')) as steam_login
 from public.profiles p left join auth.users u on u.id=p.id
 left join public.admin_users au on au.user_id=p.id
 where v_query='' or p.id::text ilike '%'||v_query||'%'
 or coalesce(p.username,'') ilike '%'||v_query||'%'
 or coalesce(p.steam_name,'') ilike '%'||v_query||'%'
 or coalesce(p.steam_id,'') ilike '%'||v_query||'%'
 or (p.contact_email_verified_at is not null and coalesce(p.contact_email,'') ilike '%'||v_query||'%')
 or (coalesce(u.email,'') not ilike '%@steam.skinquestcs.com' and coalesce(u.email,'') ilike '%'||v_query||'%')
 ), filtered as (
 select * from base where (v_role='all' or role=v_role or (v_role='staff' and role in ('admin','owner')))
 and (v_login='all' or (v_login='steam' and steam_login) or (v_login='other' and not steam_login))
 ), ordered as (
 select f.*,row_number() over(order by
 case when v_sort='newest' then created_at end desc nulls last,
 case when v_sort='oldest' then created_at end asc nulls last,
 case when v_sort='coins-desc' then points_balance end desc,
 case when v_sort='coins-asc' then points_balance end asc,
 case when v_sort='role' then case role when 'owner' then 0 when 'admin' then 1 else 2 end end asc,
 case when v_sort='name' then lower(coalesce(nullif(steam_name,''),nullif(username,''),contact_email,email,user_id::text)) end asc,
 user_id asc) as row_num from filtered f
 ), page as (
 select * from ordered where row_num>v_offset and row_num<=v_offset+v_limit
 ), enriched as (
 select p.*,
 (select count(*) from public.redemption_requests r where r.user_id=p.user_id) as order_count,
 (select count(*) from public.redemption_requests r where r.user_id=p.user_id and r.status='completed') as completed_count,
 (select count(*) from public.support_requests s where s.user_id=p.user_id) as support_count
 from page p
 )
 select jsonb_build_object('total',(select count(*) from filtered),
 'items',coalesce((select jsonb_agg(to_jsonb(e)-'row_num' order by e.row_num) from enriched e),'[]'::jsonb))
 );
end;
$$;
revoke all on function public.sq_admin_filter_users(text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_filter_users(text,text,text,text,integer,integer) to authenticated;
commit;
notify pgrst,'reload schema';
