-- SkinQuest v9.4 Supabase patch
-- Run after v9.0/v9.3 SQL. Adds email-confirm/profile fallback and admin coin testing tools.

-- Keep both old and new price columns working.
alter table public.reward_items
  add column if not exists points_coins integer,
  add column if not exists points_cost integer;

update public.reward_items
set points_coins = coalesce(points_coins, points_cost, 100)
where points_coins is null;

update public.reward_items
set points_cost = coalesce(points_cost, points_coins, 100)
where points_cost is null;

alter table public.reward_items alter column points_coins set default 100;
alter table public.reward_items alter column points_cost set default 100;

-- Make sure profile rows exist for normal users.
create or replace function public.ensure_skinquest_profile()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := coalesce(auth.jwt() ->> 'email', '');
  v_profile public.profiles%rowtype;
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_user_id;

  if found then
    return v_profile;
  end if;

  insert into public.profiles (id, username, points_balance)
  values (
    v_user_id,
    coalesce(nullif(split_part(v_email, '@', 1), ''), 'user'),
    0
  )
  on conflict (id) do update
    set username = coalesce(public.profiles.username, excluded.username)
  returning * into v_profile;

  return v_profile;
end;
$$;

grant execute on function public.ensure_skinquest_profile() to authenticated;

-- Also create profiles automatically for new email users when possible.
create or replace function public.handle_new_skinquest_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, points_balance)
  values (
    new.id,
    coalesce(nullif(split_part(new.email, '@', 1), ''), 'user'),
    0
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_skinquest on auth.users;
create trigger on_auth_user_created_skinquest
after insert on auth.users
for each row execute function public.handle_new_skinquest_user();

-- Keep existing v9 admin check.
create or replace function public.is_skinquest_admin()
returns boolean
language sql
stable
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'harrygotesson@gmail.com';
$$;

grant execute on function public.is_skinquest_admin() to anon, authenticated;

-- Normal users should be able to read/update their own profile. Admin can read/update all.
alter table public.profiles enable row level security;

drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;

create policy "Users can read own profile"
on public.profiles
for select
using (auth.uid() = id or public.is_skinquest_admin());

create policy "Users can insert own profile"
on public.profiles
for insert
with check (auth.uid() = id);

create policy "Users can update own profile"
on public.profiles
for update
using (auth.uid() = id or public.is_skinquest_admin())
with check (auth.uid() = id or public.is_skinquest_admin());

-- Make redemption-request policies explicit again.
alter table public.redemption_requests enable row level security;

drop policy if exists "Users can read own redemption requests" on public.redemption_requests;
drop policy if exists "Users can insert own redemption requests" on public.redemption_requests;
drop policy if exists "Admin can read all redemption requests" on public.redemption_requests;
drop policy if exists "Admin can update all redemption requests" on public.redemption_requests;

create policy "Users can read own redemption requests"
on public.redemption_requests
for select
using (auth.uid() = user_id or public.is_skinquest_admin());

create policy "Users can insert own redemption requests"
on public.redemption_requests
for insert
with check (auth.uid() = user_id);

create policy "Admin can update all redemption requests"
on public.redemption_requests
for update
using (public.is_skinquest_admin())
with check (public.is_skinquest_admin());

-- Recreate redeem_reward so it creates the user's profile if it is missing.
create or replace function public.redeem_reward(p_reward_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := coalesce(auth.jwt() ->> 'email', '');
  v_profile public.profiles%rowtype;
  v_reward public.reward_items%rowtype;
  v_cost integer;
  v_available integer;
  v_request_id bigint;
begin
  if v_user_id is null then
    raise exception 'You must be logged in to redeem rewards.';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  if not found then
    insert into public.profiles (id, username, points_balance)
    values (
      v_user_id,
      coalesce(nullif(split_part(v_email, '@', 1), ''), 'user'),
      0
    )
    on conflict (id) do update
      set username = coalesce(public.profiles.username, excluded.username)
    returning * into v_profile;
  end if;

  if coalesce(v_profile.steam_trade_url, '') = '' then
    raise exception 'Save your Steam trade URL before redeeming.';
  end if;

  select * into v_reward
  from public.reward_items
  where id = p_reward_id and active = true
  for update;

  if not found then
    raise exception 'Reward not found or inactive.';
  end if;

  v_cost := coalesce(v_reward.points_coins, v_reward.points_cost, 0);

  if v_cost <= 0 then
    raise exception 'Reward has an invalid coin price.';
  end if;

  v_available := coalesce(v_reward.quantity_total, 0) - coalesce(v_reward.quantity_reserved, 0);

  if v_available <= 0 then
    raise exception 'That reward is out of stock.';
  end if;

  if coalesce(v_profile.points_balance, 0) < v_cost then
    raise exception 'Not enough coins.';
  end if;

  update public.profiles
  set points_balance = points_balance - v_cost
  where id = v_user_id;

  update public.reward_items
  set quantity_reserved = quantity_reserved + 1
  where id = p_reward_id;

  insert into public.redemption_requests (
    user_id,
    reward_item_id,
    reward_name,
    points_cost,
    steam_trade_url,
    status,
    status_updated_at
  ) values (
    v_user_id,
    v_reward.id,
    v_reward.name,
    v_cost,
    v_profile.steam_trade_url,
    'pending',
    now()
  ) returning id into v_request_id;

  insert into public.coin_adjustments (user_id, amount, reason)
  values (v_user_id, -v_cost, 'Redeem pending / ' || v_reward.name);

  return jsonb_build_object('ok', true, 'request_id', v_request_id);
end;
$$;

grant execute on function public.redeem_reward(bigint) to authenticated;

-- Admin testing tool: add/remove coins by email or uuid.
create or replace function public.admin_adjust_user_coins(
  p_user_identifier text,
  p_amount integer,
  p_reason text default 'Manual admin adjustment'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_id uuid;
  v_email text;
  v_profile public.profiles%rowtype;
begin
  if not public.is_skinquest_admin() then
    raise exception 'Admin access required.';
  end if;

  if p_user_identifier is null or length(trim(p_user_identifier)) = 0 then
    raise exception 'Enter a user email or user id.';
  end if;

  if coalesce(p_amount, 0) = 0 then
    raise exception 'Amount cannot be 0.';
  end if;

  if position('@' in p_user_identifier) > 0 then
    select id, email into v_target_id, v_email
    from auth.users
    where lower(email) = lower(trim(p_user_identifier))
    limit 1;
  else
    begin
      v_target_id := trim(p_user_identifier)::uuid;
    exception when invalid_text_representation then
      raise exception 'User identifier must be an email or uuid.';
    end;
  end if;

  if v_target_id is null then
    raise exception 'User was not found. They may need to sign up/confirm/login once first.';
  end if;

  insert into public.profiles (id, username, points_balance)
  values (
    v_target_id,
    coalesce(nullif(split_part(coalesce(v_email, ''), '@', 1), ''), 'user'),
    0
  )
  on conflict (id) do nothing;

  update public.profiles
  set points_balance = coalesce(points_balance, 0) + p_amount
  where id = v_target_id
  returning * into v_profile;

  insert into public.coin_adjustments (user_id, amount, reason)
  values (v_target_id, p_amount, coalesce(nullif(p_reason, ''), 'Manual admin adjustment'));

  return jsonb_build_object('ok', true, 'user_id', v_target_id, 'new_balance', v_profile.points_balance);
end;
$$;

grant execute on function public.admin_adjust_user_coins(text, integer, text) to authenticated;
