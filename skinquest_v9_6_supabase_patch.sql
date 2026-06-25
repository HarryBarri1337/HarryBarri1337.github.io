-- SkinQuest v9.6 Supabase patch
-- Fixes normal-user Steam trade URL saving so redeem does not silently bounce users to Dashboard.

create or replace function public.save_skinquest_trade_url(p_trade_url text)
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

  if coalesce(p_trade_url, '') <> '' and p_trade_url not like 'https://steamcommunity.com/tradeoffer/new/%' then
    raise exception 'Invalid Steam trade URL.';
  end if;

  insert into public.profiles (id, username, points_balance, steam_trade_url)
  values (
    v_user_id,
    coalesce(nullif(split_part(v_email, '@', 1), ''), 'user'),
    0,
    nullif(p_trade_url, '')
  )
  on conflict (id) do update
    set steam_trade_url = excluded.steam_trade_url
  returning * into v_profile;

  return v_profile;
end;
$$;

grant execute on function public.save_skinquest_trade_url(text) to authenticated;
