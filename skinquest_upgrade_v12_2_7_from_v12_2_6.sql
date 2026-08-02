-- SkinQuest v12.2.7 upgrade
-- Repairs Steam trade URL saving for existing Supabase projects.

alter table public.profiles
  add column if not exists steam_trade_url text;

create or replace function public.save_skinquest_trade_url(p_trade_url text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_trade_url text := nullif(trim(coalesce(p_trade_url, '')), '');
begin
  if v_user_id is null then
    raise exception 'You must be logged in.';
  end if;

  perform public.ensure_skinquest_profile();

  if v_trade_url is not null and (
    v_trade_url !~* '^https://(www\.)?steamcommunity\.com/tradeoffer/new/?\?' or
    v_trade_url !~ '(^|[?&])partner=[0-9]+(&|$)' or
    v_trade_url !~ '(^|[?&])token=[A-Za-z0-9_-]+(&|$)'
  ) then
    raise exception 'Invalid Steam trade URL.';
  end if;

  update public.profiles
  set steam_trade_url = v_trade_url,
      updated_at = now()
  where id = v_user_id
  returning * into v_profile;

  if v_profile.id is null then
    raise exception 'Could not find or create your profile.';
  end if;

  return v_profile;
end;
$$;

revoke all on function public.save_skinquest_trade_url(text) from public;
grant execute on function public.save_skinquest_trade_url(text) to authenticated;

-- Restricted fallback used only if the RPC call is unavailable.
grant update (steam_trade_url) on public.profiles to authenticated;

drop policy if exists profiles_update_own_trade_url on public.profiles;
create policy profiles_update_own_trade_url on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());
