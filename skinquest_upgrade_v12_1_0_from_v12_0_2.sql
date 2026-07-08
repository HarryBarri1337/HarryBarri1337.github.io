-- SkinQuest v12.1.0 upgrade from v12.0.2
-- Adds admin-only notification subscriber views so owner/admin accounts can see emails by notification preference.
-- Run this in Supabase SQL Editor on the existing live project.

-- Important: profiles.username is not guaranteed to be a full email.
-- SkinQuest currently creates username from the email prefix in some flows.
-- These views use auth.users.email as the real email source, then fall back to username only if it looks like an email.

drop view if exists public.admin_notification_reward_update_emails;
drop view if exists public.admin_notification_offer_issue_emails;
drop view if exists public.admin_notification_product_update_emails;
drop view if exists public.admin_notification_subscribers;

create or replace view public.admin_notification_subscribers as
select
  p.id as user_id,
  coalesce(u.email, case when p.username like '%@%' then p.username else null end) as email,
  p.username,
  p.steam_id,
  p.steam_name,
  coalesce(p.notification_reward_updates, true) as reward_updates,
  coalesce(p.notification_offer_issues, true) as offer_issues,
  coalesce(p.notification_product_updates, false) as product_updates,
  p.account_status,
  p.created_at,
  p.updated_at,
  u.email_confirmed_at,
  u.last_sign_in_at
from public.profiles p
left join auth.users u on u.id = p.id
where public.is_admin();

create or replace view public.admin_notification_reward_update_emails as
select *
from public.admin_notification_subscribers
where reward_updates = true
  and email is not null;

create or replace view public.admin_notification_offer_issue_emails as
select *
from public.admin_notification_subscribers
where offer_issues = true
  and email is not null;

create or replace view public.admin_notification_product_update_emails as
select *
from public.admin_notification_subscribers
where product_updates = true
  and email is not null;

grant select on public.admin_notification_subscribers to authenticated;
grant select on public.admin_notification_reward_update_emails to authenticated;
grant select on public.admin_notification_offer_issue_emails to authenticated;
grant select on public.admin_notification_product_update_emails to authenticated;
