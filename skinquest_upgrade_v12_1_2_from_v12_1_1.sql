-- SkinQuest upgrade v12.1.2 from v12.1.1
-- Run this in Supabase SQL Editor on an existing v12.1.1 project.
-- Adds goal rewards: users can star up to 5 reward_items to track on the dashboard.

-- -----------------------------
-- Table
-- -----------------------------

create table if not exists public.favorite_rewards (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  reward_id bigint not null references public.reward_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(user_id, reward_id)
);

create index if not exists favorite_rewards_user_idx on public.favorite_rewards(user_id, created_at desc);
create index if not exists favorite_rewards_reward_idx on public.favorite_rewards(reward_id);

-- -----------------------------
-- Trigger: cap goal rewards at 5 per user
-- -----------------------------

create or replace function public.enforce_favorite_reward_limit()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.favorite_rewards where user_id = new.user_id) >= 5 then
    raise exception 'You can only star up to 5 rewards as goals.';
  end if;
  return new;
end;
$$;

drop trigger if exists favorite_rewards_limit_trg on public.favorite_rewards;
create trigger favorite_rewards_limit_trg
before insert on public.favorite_rewards
for each row execute function public.enforce_favorite_reward_limit();

-- -----------------------------
-- RLS policies
-- -----------------------------

alter table public.favorite_rewards enable row level security;

drop policy if exists favorite_rewards_select_own on public.favorite_rewards;
create policy favorite_rewards_select_own on public.favorite_rewards
for select to authenticated
using (user_id = auth.uid());

drop policy if exists favorite_rewards_insert_own on public.favorite_rewards;
create policy favorite_rewards_insert_own on public.favorite_rewards
for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists favorite_rewards_delete_own on public.favorite_rewards;
create policy favorite_rewards_delete_own on public.favorite_rewards
for delete to authenticated
using (user_id = auth.uid());

-- -----------------------------
-- Grants
-- -----------------------------

grant select, insert, delete on public.favorite_rewards to authenticated;
grant usage, select on all sequences in schema public to authenticated;
