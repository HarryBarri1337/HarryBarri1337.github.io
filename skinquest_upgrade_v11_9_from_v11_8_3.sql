-- SkinQuest upgrade v11.9 from v11.8.3
-- Adds database support for Steam account connection.

alter table public.profiles
add column if not exists steam_connected_at timestamptz;

create unique index if not exists profiles_steam_id_unique_idx
on public.profiles (steam_id)
where steam_id is not null;

create table if not exists public.steam_auth_states (
  state text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.steam_auth_states enable row level security;

create index if not exists steam_auth_states_user_id_idx
on public.steam_auth_states (user_id);

create index if not exists steam_auth_states_expires_at_idx
on public.steam_auth_states (expires_at);
