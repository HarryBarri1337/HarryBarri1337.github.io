-- SkinQuest upgrade v11.8.3 from v11.8.2
-- Support widget email requirement + public support insert policy.
-- Run this in Supabase SQL Editor before/when deploying v11.8.3.

-- Allow guests and signed-in users to submit support requests with a reply email.
drop policy if exists support_requests_insert_own on public.support_requests;
drop policy if exists support_requests_insert_contact on public.support_requests;
create policy support_requests_insert_contact on public.support_requests
for insert to anon, authenticated
with check (
  (user_id is null or user_id = auth.uid())
  and account_email is not null
  and position('@' in account_email) > 1
  and char_length(account_email) <= 254
  and char_length(topic) between 2 and 80
  and char_length(message) between 8 and 1800
);

grant insert on public.support_requests to anon;
grant usage, select on public.support_requests_id_seq to anon;

-- Email notification is handled by the Supabase Edge Function in:
-- supabase/functions/support-notify/index.ts
-- Deploy it and connect a Database Webhook on INSERT for public.support_requests.
