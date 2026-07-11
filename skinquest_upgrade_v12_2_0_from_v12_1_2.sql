-- SkinQuest upgrade v12.2.0 from v12.1.2
-- Run this in Supabase SQL Editor on an existing v12.1.2 project.
-- Raises the goal rewards (favorite_rewards) star limit from 5 to 6 per user.

create or replace function public.enforce_favorite_reward_limit()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.favorite_rewards where user_id = new.user_id) >= 6 then
    raise exception 'You can only star up to 6 rewards as goals.';
  end if;
  return new;
end;
$$;
