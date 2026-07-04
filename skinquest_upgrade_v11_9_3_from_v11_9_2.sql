-- SkinQuest upgrade v11.9.3 from v11.9.2
-- Adds support for Steam sign-up/sign-in and Steam disconnect.
-- Run this in Supabase SQL Editor before testing v11.9.3 Steam auth.

alter table public.steam_auth_states alter column user_id drop not null;
alter table public.steam_auth_states add column if not exists mode text not null default 'connect';

create unique index if not exists profiles_steam_id_unique_idx
on public.profiles (steam_id)
where steam_id is not null;

select 'SkinQuest v11.9.3 Steam auth database upgrade complete' as status;
