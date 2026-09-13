-- SkinQuest v14.5.4 -> v14.5.5. Back up first; run only this upgrade.
begin;
create index if not exists sq_cpx_open_analytics_idx
on public.sq_product_events(user_id) where event_name='cpx_wall_open_requested';
create index if not exists sq_cpx_completed_analytics_idx
on public.offerwall_events(user_id) where provider='cpx' and status='completed';

create or replace function public.sq_admin_users_activity(
 p_query text default null,p_role text default 'all',p_login text default 'all',
 p_sort text default 'newest',p_limit integer default 75,p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path=public,auth
as $$
declare v_result jsonb; v_items jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 v_result:=public.sq_admin_filter_users(p_query,p_role,p_login,p_sort,p_limit,p_offset);
 select coalesce(jsonb_agg(
   e.item || jsonb_build_object(
    'account_created_at',u.created_at,
    'verified_cpx_rewards',(select count(*) from public.offerwall_events o
      where o.user_id=u.id and o.provider='cpx' and o.status='completed'),
    'cpx_opens',(select count(*) from public.sq_product_events p
      where p.user_id=u.id and p.event_name='cpx_wall_open_requested')
   ) order by e.ord),'[]'::jsonb)
 into v_items
 from jsonb_array_elements(v_result->'items') with ordinality as e(item,ord)
 left join auth.users u on u.id=(e.item->>'user_id')::uuid;
 return v_result || jsonb_build_object('items',v_items);
end;
$$;
revoke all on function public.sq_admin_users_activity(text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_users_activity(text,text,text,text,integer,integer) to authenticated;
commit;
notify pgrst,'reload schema';
