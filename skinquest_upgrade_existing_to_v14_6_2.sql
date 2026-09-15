-- SkinQuest v14.6.2 delta for an EXISTING v14.6.1 installation.
-- Backup first. Do not run the full setup file on an existing database.
begin;

do $$
declare definition text;
begin
  select pg_get_functiondef('public.process_offerwall_postback(text,text,uuid,integer,text,jsonb)'::regprocedure)
    into definition;
  if position('(''cpx'', ''bitlabs'', ''lootably'')' in definition) = 0 then
    raise exception 'Unexpected existing offerwall function: upgrade requires v14.6.1.';
  end if;
  execute replace(definition, '(''cpx'', ''bitlabs'', ''lootably'')',
    '(''cpx'', ''bitlabs'', ''lootably'', ''timewall'')');
end;
$$;

create or replace function public.sq_process_timewall_postback(
  p_event_id text, p_user_id uuid, p_amount integer, p_revenue text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_event public.offerwall_events%rowtype;
begin
  if auth.role() <> 'service_role' then raise exception 'Service role required.'; end if;
  if p_amount < 1 or p_amount > 5000 then raise exception 'Event limit exceeded.'; end if;
  if p_revenue is null or length(p_revenue) > 40 then raise exception 'Invalid revenue.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 10452));
  select * into v_event from public.offerwall_events
   where provider='timewall' and provider_event_id=p_event_id;
  if not found and coalesce((select sum(amount) from public.offerwall_events
      where provider='timewall' and user_id=p_user_id and status='completed'
      and processed_at > now()-interval '24 hours'), 0) + p_amount > 15000
    then raise exception 'TimeWall daily limit exceeded.'; end if;
  return public.process_offerwall_postback('timewall', p_event_id, p_user_id,
    p_amount, 'completed', jsonb_build_object('revenue_usd',p_revenue,'coins',p_amount));
end;
$$;
revoke all on function public.sq_process_timewall_postback(text,uuid,integer,text) from public,anon,authenticated;
grant execute on function public.sq_process_timewall_postback(text,uuid,integer,text) to service_role;
commit;
