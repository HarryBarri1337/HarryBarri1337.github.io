-- SkinQuest v10.0 Supabase patch
-- Adds automatic 50 coin level rewards. Users level up every 1,000 earned coins.

alter table public.profiles
  add column if not exists level_bonus_claimed_up_to integer not null default 1;

create or replace function public.claim_level_rewards()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := coalesce(auth.jwt() ->> 'email', '');
  v_profile public.profiles%rowtype;
  v_base_earned integer := 0;
  v_current_level integer := 1;
  v_claimed_level integer := 1;
  v_bonus integer := 0;
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  insert into public.profiles (id, username, points_balance, level_bonus_claimed_up_to)
  values (
    v_user_id,
    coalesce(nullif(split_part(v_email, '@', 1), ''), 'user'),
    0,
    1
  )
  on conflict (id) do nothing;

  select * into v_profile
  from public.profiles
  where id = v_user_id
  for update;

  select coalesce(sum(amount), 0)::integer into v_base_earned
  from public.coin_adjustments
  where user_id = v_user_id
    and amount > 0
    and lower(coalesce(reason, '')) not like 'level reward%';

  v_current_level := greatest(1, floor(v_base_earned / 1000.0)::integer + 1);
  v_claimed_level := greatest(1, coalesce(v_profile.level_bonus_claimed_up_to, 1));

  if v_current_level > v_claimed_level then
    v_bonus := (v_current_level - v_claimed_level) * 50;

    update public.profiles
    set points_balance = coalesce(points_balance, 0) + v_bonus,
        level_bonus_claimed_up_to = v_current_level
    where id = v_user_id;

    insert into public.coin_adjustments (user_id, amount, reason)
    values (
      v_user_id,
      v_bonus,
      'Level reward / Level ' || (v_claimed_level + 1)::text || case when v_current_level > v_claimed_level + 1 then ' to ' || v_current_level::text else '' end
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'earned_coins', v_base_earned,
    'level', v_current_level,
    'claimed_level', greatest(v_claimed_level, v_current_level),
    'bonus_awarded', v_bonus
  );
end;
$$;

grant execute on function public.claim_level_rewards() to authenticated;
