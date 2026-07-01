-- SkinQuest v11.5 upgrade-only SQL
-- Run this if you already have the v11.4 database setup.
-- Adds support context fields used by v11.5 admin support inbox.

alter table public.support_requests add column if not exists page_url text;
alter table public.support_requests add column if not exists user_agent text;
alter table public.support_requests add column if not exists account_email text;
alter table public.support_requests add column if not exists browser_language text;
alter table public.support_requests add column if not exists admin_note text;
alter table public.support_requests add column if not exists updated_at timestamptz not null default now();

create index if not exists support_requests_status_created_idx on public.support_requests(status, created_at desc);
create index if not exists support_requests_user_created_idx on public.support_requests(user_id, created_at desc);

-- Quick verification
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'support_requests'
  and column_name in ('page_url', 'user_agent', 'account_email', 'browser_language', 'admin_note', 'updated_at')
order by column_name;
