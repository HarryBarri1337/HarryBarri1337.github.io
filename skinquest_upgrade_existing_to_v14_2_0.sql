-- SkinQuest upgrade for EXISTING projects -> v14.2.0
-- Safe to run when upgrading from v14.1.3 OR v14.1.4.
-- Run this ONCE in Supabase SQL Editor.
-- Includes the v14.1.4 private notification fix and adds a server-side
-- one-password-reset-email-per-minute limiter used by password-reset-request.

begin;

-- v14.1.4 notification privacy fix, retained here so users can skip directly
-- from v14.1.3 to v14.2.0.
drop policy if exists "sq own notifications read" on public.sq_notifications;
create policy "sq own notifications read"
on public.sq_notifications for select
using (auth.uid() = user_id);

-- v14.2.0 password reset cooldown. Only the service-role Edge Function can
-- read/write this table; browser clients receive no direct access.
create table if not exists public.password_reset_rate_limits (
  key_hash text primary key,
  last_sent_at timestamptz not null default now()
);

alter table public.password_reset_rate_limits enable row level security;
revoke all on public.password_reset_rate_limits from public, anon, authenticated;

create or replace function public.claim_password_reset_rate_limit(p_key_hash text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_last timestamptz;
  v_retry integer;
begin
  if p_key_hash is null or length(trim(p_key_hash)) < 16 then
    raise exception 'Invalid rate-limit key.';
  end if;

  -- Serialize requests for the same hashed email so two simultaneous clicks
  -- cannot both pass the cooldown check.
  perform pg_advisory_xact_lock(hashtextextended(p_key_hash, 0));

  select last_sent_at
    into v_last
    from public.password_reset_rate_limits
   where key_hash = p_key_hash;

  if v_last is not null and v_last > v_now - interval '60 seconds' then
    v_retry := greatest(
      1,
      ceil(extract(epoch from ((v_last + interval '60 seconds') - v_now)))::integer
    );
    return v_retry;
  end if;

  insert into public.password_reset_rate_limits(key_hash, last_sent_at)
  values (p_key_hash, v_now)
  on conflict (key_hash) do update
    set last_sent_at = excluded.last_sent_at;

  return 0;
end;
$$;

revoke all on function public.claim_password_reset_rate_limit(text) from public, anon, authenticated;
grant execute on function public.claim_password_reset_rate_limit(text) to service_role;

notify pgrst, 'reload schema';
commit;
