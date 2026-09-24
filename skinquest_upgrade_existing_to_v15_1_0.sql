-- SkinQuest v15.1.0. Apply once to an existing v15.0.5 database before uploading the site.
-- Giveaways use verified postback records; no client-side claim can grant entry.
begin;

-- Tell the admin page when pagination has loaded only part of a delivery.
-- Shared actions stay disabled until the full list is visible.
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
   order by r.user_id,r.delivery_id nulls last,r.created_at,r.id
   limit greatest(1,least(coalesce(p_limit,100),1000)) offset greatest(0,coalesce(p_offset,0))) t),'[]'::jsonb),
  'total',(select count(*) from public.redemption_requests where status not in ('completed','rejected','refunded','cancelled')));
end $$;
revoke all on function public.sq_admin_delivery_orders(integer,integer) from public,anon,authenticated;
grant execute on function public.sq_admin_delivery_orders(integer,integer) to authenticated;

-- Provider events show whether verified callbacks have reached this database.
-- This cannot inspect TimeWall's dashboard, placement, or secret settings.
create or replace function public.sq_admin_timewall_status()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 return jsonb_build_object(
   'completed',(select count(*) from public.offerwall_events where provider='timewall' and status='completed'),
   'reversed',(select count(*) from public.offerwall_events where provider='timewall' and status='reversed'),
   'last_completed_at',(select max(created_at) from public.offerwall_events where provider='timewall' and status='completed'),
   'last_event_at',(select max(processed_at) from public.offerwall_events where provider='timewall')
 );
end $$;
revoke all on function public.sq_admin_timewall_status() from public,anon,authenticated;
grant execute on function public.sq_admin_timewall_status() to authenticated;

create table if not exists public.sq_giveaways (
  id uuid primary key default gen_random_uuid(),
  reward_id bigint references public.reward_items(id) on delete set null,
  reward_name text not null,
  reward_image text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  ends_at timestamptz not null,
  state text not null default 'open' check (state in ('open','drawn','cancelled','closed')),
  winner_user_id uuid references auth.users(id) on delete set null,
  drawn_at timestamptz,
  delivered_at timestamptz,
  delivered_by uuid references auth.users(id) on delete set null,
  trade_offer_url text,
  check (ends_at > created_at)
);
create table if not exists public.sq_giveaway_entries (
  id bigint generated always as identity primary key,
  giveaway_id uuid not null references public.sq_giveaways(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  qualifying_event_id bigint not null references public.offerwall_events(id) on delete restrict,
  entered_at timestamptz not null default now(),
  unique(giveaway_id,user_id)
);
create index if not exists sq_giveaway_entries_draw_idx on public.sq_giveaway_entries(giveaway_id,entered_at);
create index if not exists sq_giveaway_surveys_idx on public.offerwall_events(user_id,created_at)
  where status='completed' and amount>0 and provider in ('cpx','cpx-research','cpx_research','timewall');
alter table public.sq_giveaways enable row level security;
alter table public.sq_giveaway_entries enable row level security;
revoke all on public.sq_giveaways,public.sq_giveaway_entries from public,anon,authenticated;

-- A reward is credited by a real provider callback. TimeWall Earn tasks do not count.
-- CPX can pay for a screen-out; this is therefore a verified survey reward,
-- not proof that every questionnaire was finished.
create or replace function public.sq_giveaway_qualifying_event(p_user uuid,p_opened timestamptz,p_ends timestamptz)
returns bigint language sql stable security definer set search_path=public as $$
  select e.id from public.offerwall_events e
  where e.user_id=p_user and e.status='completed' and e.amount>0
    and e.created_at>=p_opened and e.created_at<p_ends
    and (e.provider in ('cpx','cpx-research','cpx_research')
      or (e.provider='timewall' and e.raw_payload->>'earning_source'='timewall_surveys'))
  order by e.created_at,e.id limit 1;
$$;
revoke all on function public.sq_giveaway_qualifying_event(uuid,timestamptz,timestamptz) from public,anon,authenticated;

create or replace function public.sq_giveaway_feed()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_user uuid:=auth.uid();
begin
 return jsonb_build_object('active',coalesce((select jsonb_agg(jsonb_build_object(
  'id',g.id,'reward_name',g.reward_name,'reward_image',g.reward_image,
  'created_at',g.created_at,'ends_at',g.ends_at,'state',g.state,
  'entry_count',(select count(*) from public.sq_giveaway_entries e where e.giveaway_id=g.id),
  'entered',exists(select 1 from public.sq_giveaway_entries e where e.giveaway_id=g.id and e.user_id=v_user),
  'eligible',v_user is not null and public.sq_giveaway_qualifying_event(v_user,g.created_at,g.ends_at) is not null
 ) order by g.ends_at) from public.sq_giveaways g
 where g.state='open' and g.ends_at>now()),'[]'::jsonb),
 'recent',coalesce((select jsonb_agg(jsonb_build_object(
   'id',g.id,'reward_name',g.reward_name,'ends_at',g.ends_at,
   'state',case when g.state='open' then 'awaiting_draw' else g.state end,
   'entry_count',(select count(*) from public.sq_giveaway_entries e where e.giveaway_id=g.id),
   'entered',exists(select 1 from public.sq_giveaway_entries e where e.giveaway_id=g.id and e.user_id=v_user),
   'won',v_user is not null and g.winner_user_id=v_user
 ) order by g.ends_at desc) from
 (select * from public.sq_giveaways where state<>'open' or ends_at<=now()
  order by ends_at desc limit 8) g),'[]'::jsonb));
end $$;
revoke all on function public.sq_giveaway_feed() from public,anon,authenticated;
grant execute on function public.sq_giveaway_feed() to anon,authenticated;

create or replace function public.sq_giveaway_enter(p_giveaway_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_g public.sq_giveaways%rowtype; v_event bigint;
begin
 if v_user is null then raise exception 'Sign in before entering.'; end if;
 select * into v_g from public.sq_giveaways where id=p_giveaway_id for update;
 if not found or v_g.state<>'open' or v_g.ends_at<=now() then raise exception 'This giveaway is closed.'; end if;
 if exists(select 1 from public.sq_giveaway_entries where giveaway_id=p_giveaway_id and user_id=v_user) then
  return jsonb_build_object('ok',true,'already_entered',true);
 end if;
 v_event:=public.sq_giveaway_qualifying_event(v_user,v_g.created_at,v_g.ends_at);
 if v_event is null then raise exception 'Earn a verified survey reward after this giveaway opens, then enter.'; end if;
 insert into public.sq_giveaway_entries(giveaway_id,user_id,qualifying_event_id)
 values(p_giveaway_id,v_user,v_event) on conflict(giveaway_id,user_id) do nothing;
 return jsonb_build_object('ok',true,'already_entered',false);
end $$;
revoke all on function public.sq_giveaway_enter(uuid) from public,anon,authenticated;
grant execute on function public.sq_giveaway_enter(uuid) to authenticated;

create or replace function public.sq_admin_giveaway_create(p_reward_id bigint,p_ends_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_reward public.reward_items%rowtype; v_g public.sq_giveaways%rowtype; v_end timestamptz:=coalesce(p_ends_at,now()+interval '8 days');
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if v_end<now()+interval '1 hour' or v_end>now()+interval '90 days' then
  raise exception 'Choose an end time from one hour to 90 days away.';
 end if;
 select * into v_reward from public.reward_items where id=p_reward_id and active=true;
 if not found then raise exception 'Choose an active catalog reward.'; end if;
 insert into public.sq_giveaways(reward_id,reward_name,reward_image,created_by,ends_at)
 values(v_reward.id,v_reward.name,v_reward.image_url,auth.uid(),v_end) returning * into v_g;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'giveaway_created','giveaway',v_g.id::text,jsonb_build_object('reward_id',p_reward_id,'reward_name',v_g.reward_name,'ends_at',v_end));
 return jsonb_build_object('id',v_g.id,'ends_at',v_g.ends_at);
end $$;
revoke all on function public.sq_admin_giveaway_create(bigint,timestamptz) from public,anon,authenticated;
grant execute on function public.sq_admin_giveaway_create(bigint,timestamptz) to authenticated;

create or replace function public.sq_admin_giveaways()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',g.id,'reward_name',g.reward_name,'reward_image',g.reward_image,
  'created_at',g.created_at,'ends_at',g.ends_at,'state',g.state,
  'winner_user_id',g.winner_user_id,'drawn_at',g.drawn_at,
  'delivered_at',g.delivered_at,'trade_offer_url',g.trade_offer_url,
  'winner_name',p.steam_name,'winner_email',case when p.contact_email_verified_at is not null then p.contact_email end,
  'winner_trade_url',p.steam_trade_url,
  'entry_count',(select count(*) from public.sq_giveaway_entries e where e.giveaway_id=g.id),
  'valid_entries',(select count(*) from public.sq_giveaway_entries e where e.giveaway_id=g.id
    and public.sq_giveaway_qualifying_event(e.user_id,g.created_at,g.ends_at) is not null)
 ) order by g.created_at desc) from
 (select * from public.sq_giveaways order by created_at desc limit 100) g
 left join public.profiles p on p.id=g.winner_user_id),'[]'::jsonb);
end $$;
revoke all on function public.sq_admin_giveaways() from public,anon,authenticated;
grant execute on function public.sq_admin_giveaways() to authenticated;

create or replace function public.sq_admin_giveaway_draw(p_giveaway_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_g public.sq_giveaways%rowtype; v_winner uuid; v_count integer;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 select * into v_g from public.sq_giveaways where id=p_giveaway_id for update;
 if not found or v_g.state<>'open' then raise exception 'This giveaway was already closed.'; end if;
 if v_g.ends_at>now() then raise exception 'Wait until the giveaway ends before drawing.'; end if;
 select count(*) into v_count from public.sq_giveaway_entries e
 where e.giveaway_id=v_g.id and public.sq_giveaway_qualifying_event(e.user_id,v_g.created_at,v_g.ends_at) is not null;
 select e.user_id into v_winner from public.sq_giveaway_entries e
 where e.giveaway_id=v_g.id and public.sq_giveaway_qualifying_event(e.user_id,v_g.created_at,v_g.ends_at) is not null
 order by gen_random_uuid() limit 1;
 update public.sq_giveaways set state=case when v_winner is null then 'closed' else 'drawn' end,
 winner_user_id=v_winner,drawn_at=now() where id=v_g.id;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'giveaway_drawn','giveaway',v_g.id::text,
  jsonb_build_object('winner_user_id',v_winner,'valid_entries',v_count,'reward_name',v_g.reward_name));
 return jsonb_build_object('winner_user_id',v_winner,'valid_entries',v_count);
end $$;
revoke all on function public.sq_admin_giveaway_draw(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_giveaway_draw(uuid) to authenticated;

create or replace function public.sq_admin_giveaway_cancel(p_giveaway_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_g public.sq_giveaways%rowtype;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 select * into v_g from public.sq_giveaways where id=p_giveaway_id for update;
 if not found or v_g.state<>'open' then raise exception 'Only an open giveaway can be cancelled.'; end if;
 update public.sq_giveaways set state='cancelled' where id=p_giveaway_id;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'giveaway_cancelled','giveaway',v_g.id::text,jsonb_build_object('reward_name',v_g.reward_name,'entries',(select count(*) from public.sq_giveaway_entries where giveaway_id=v_g.id)));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.sq_admin_giveaway_cancel(uuid) from public,anon,authenticated;
grant execute on function public.sq_admin_giveaway_cancel(uuid) to authenticated;

create or replace function public.sq_admin_giveaway_delivered(p_giveaway_id uuid,p_trade_offer_url text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_g public.sq_giveaways%rowtype; v_url text:=nullif(trim(coalesce(p_trade_offer_url,'')),''); v_trade text;
begin
 if not public.is_admin() then raise exception 'Admin access required.'; end if;
 if v_url is not null and (length(v_url)>500 or
    v_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/[0-9]+/?([?#].*)?$') then
  raise exception 'Use a valid Steam offer URL or leave it blank.';
 end if;
 select * into v_g from public.sq_giveaways where id=p_giveaway_id for update;
 if not found or v_g.state<>'drawn' or v_g.winner_user_id is null or v_g.delivered_at is not null then
  raise exception 'Only a drawn, undelivered giveaway can be completed.';
 end if;
 select steam_trade_url into v_trade from public.profiles where id=v_g.winner_user_id;
 if v_trade is null or v_trade !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/\?' then
  raise exception 'The winner must save a valid Steam trade link before delivery is recorded.';
 end if;
 update public.sq_giveaways set delivered_at=now(),delivered_by=auth.uid(),trade_offer_url=v_url where id=p_giveaway_id;
 insert into public.sq_admin_audit_log(actor_user_id,action,entity_type,entity_id,details)
 values(auth.uid(),'giveaway_delivered','giveaway',v_g.id::text,
  jsonb_build_object('winner_user_id',v_g.winner_user_id,'reward_name',v_g.reward_name,'trade_offer_url',v_url));
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.sq_admin_giveaway_delivered(uuid,text) from public,anon,authenticated;
grant execute on function public.sq_admin_giveaway_delivered(uuid,text) to authenticated;

commit;
notify pgrst,'reload schema';
