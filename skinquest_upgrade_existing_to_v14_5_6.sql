-- SkinQuest v14.5.5 -> v14.5.6. Back up first; run only this upgrade.
begin;
create table if not exists public.sq_user_presence(
 user_id uuid primary key references auth.users(id) on delete cascade,
 last_active_at timestamptz not null default now()
);
alter table public.sq_user_presence enable row level security;
revoke all on public.sq_user_presence from public,anon,authenticated;
grant select on public.sq_user_presence to authenticated;
drop policy if exists sq_presence_read on public.sq_user_presence;
create policy sq_presence_read on public.sq_user_presence for select
using(user_id=auth.uid() or public.is_admin());

create or replace function public.sq_touch_activity()
returns boolean language plpgsql security definer set search_path=public,auth as $$
begin
 if auth.uid() is null then return false; end if;
 insert into public.sq_user_presence(user_id,last_active_at) values(auth.uid(),now())
 on conflict(user_id) do update set last_active_at=excluded.last_active_at
 where public.sq_user_presence.last_active_at<now()-interval '1 minute';
 return true;
end;
$$;
revoke all on function public.sq_touch_activity() from public,anon,authenticated;
grant execute on function public.sq_touch_activity() to authenticated;

create index if not exists sq_daily_last_activity_idx on public.sq_daily_activity(user_id,last_seen_at desc);
create index if not exists sq_product_last_activity_idx on public.sq_product_events(user_id,created_at desc);
create or replace function public.sq_admin_last_active(p_user_id uuid)
returns timestamptz language plpgsql stable security definer set search_path=public,auth as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 return greatest(
 (select last_active_at from public.sq_user_presence where user_id=p_user_id),
 (select max(last_seen_at) from public.sq_daily_activity where user_id=p_user_id),
 (select max(created_at) from public.sq_product_events where user_id=p_user_id));
end;
$$;
revoke all on function public.sq_admin_last_active(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_last_active(uuid) to authenticated;

create or replace function public.sq_admin_cpx_activity(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_events bigint; v_ledger bigint; v_opens bigint; v_all bigint;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 select count(*),count(*) filter(where lower(status)='completed')
 into v_all,v_events from public.offerwall_events
 where user_id=p_user_id and lower(provider) in ('cpx','cpx-research','cpx_research');
 select count(*) into v_ledger from public.coin_adjustments
 where user_id=p_user_id and amount>0
 and (lower(coalesce(source_id,'')) like 'cpx:%'
 or (source_type='offerwall_credit' and lower(coalesce(metadata->>'provider','')) in ('cpx','cpx-research','cpx_research'))
 or coalesce(reason,'') ~* '^CPX([[:space:]:_-]|$)');
 select count(*) into v_opens from public.sq_product_events
 where user_id=p_user_id and event_name='cpx_wall_open_requested';
 return jsonb_build_object(
 'completed_reward_events',case when v_all>0 then v_events else null end,
 'postback_rows',v_all,'ledger_credit_rows',nullif(v_ledger,0),
 'logged_opens',nullif(v_opens,0),
 'note','Postbacks may include screen-out compensation. Ledger counts are CPX-labelled credits, not proof of full surveys. Opens are observed CPX launch clicks, not individual surveys inside the widget.');
end;
$$;
revoke all on function public.sq_admin_cpx_activity(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_cpx_activity(uuid) to authenticated;

create or replace function public.sq_admin_users_activity(
 p_query text default null,p_role text default 'all',p_login text default 'all',
 p_sort text default 'newest',p_limit integer default 75,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_result jsonb; v_items jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 v_result:=public.sq_admin_filter_users(p_query,p_role,p_login,p_sort,p_limit,p_offset);
 select coalesce(jsonb_agg(
 e.item || jsonb_build_object('account_created_at',u.created_at,
 'last_active_at',public.sq_admin_last_active(u.id)) order by e.ord),'[]'::jsonb)
 into v_items
 from jsonb_array_elements(v_result->'items') with ordinality as e(item,ord)
 left join auth.users u on u.id=(e.item->>'user_id')::uuid;
 return v_result || jsonb_build_object('items',v_items);
end;
$$;
revoke all on function public.sq_admin_users_activity(text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_users_activity(text,text,text,text,integer,integer) to authenticated;

create or replace function public.sq_admin_user_profile(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_result jsonb; v_user jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 v_result:=public.sq_admin_users_activity(p_user_id::text,'all','all','newest',200,0);
 select e.item into v_user from jsonb_array_elements(v_result->'items') as e(item)
 where e.item->>'user_id'=p_user_id::text;
 if v_user is null then raise exception 'User not found.'; end if;
 return jsonb_build_object('user',v_user,'cpx',public.sq_admin_cpx_activity(p_user_id));
end;
$$;
revoke all on function public.sq_admin_user_profile(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_user_profile(uuid) to authenticated;

create or replace function public.sq_admin_user_records(
 p_user_id uuid,p_section text default 'orders',p_limit integer default 25,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_table text; v_columns text; v_date text; v_total bigint; v_items jsonb;
 v_limit integer:=greatest(1,least(coalesce(p_limit,25),100));
 v_offset integer:=greatest(0,coalesce(p_offset,0));
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 case p_section
 when 'orders' then v_table:='redemption_requests'; v_date:='created_at'; v_columns:='id,order_number,reward_id,reward_name,points_coins,points_cost,status,created_at';
 when 'support' then v_table:='support_requests'; v_date:='created_at'; v_columns:='id,ticket_number,topic,status,created_at';
 when 'coins' then v_table:='coin_adjustments'; v_date:='created_at'; v_columns:='id,amount,reason,source_type,source_id,created_at';
 when 'promos' then v_table:='sq_promo_redemptions'; v_date:='redeemed_at'; v_columns:='id,promo_code_id,code_snapshot,campaign_snapshot,coins_awarded,redeemed_at';
 when 'surveys' then v_table:='offerwall_events'; v_date:='created_at'; v_columns:='id,provider,provider_event_id,amount,status,created_at,processed_at';
 else raise exception 'Invalid user-history section.';
 end case;
 execute format('select count(*) from public.%I where user_id=$1',v_table)
 into v_total using p_user_id;
 execute format('select coalesce(jsonb_agg(to_jsonb(r) order by r.%I desc,r.id desc),''[]''::jsonb)
 from (select %s from public.%I where user_id=$1 order by %I desc,id desc limit $2 offset $3) r',
 v_date,v_columns,v_table,v_date)
 into v_items using p_user_id,v_limit,v_offset;
 return jsonb_build_object('items',v_items,'total',v_total,'offset',v_offset,'limit',v_limit);
end;
$$;
revoke all on function public.sq_admin_user_records(uuid,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_user_records(uuid,text,integer,integer) to authenticated;
commit;
notify pgrst,'reload schema';
