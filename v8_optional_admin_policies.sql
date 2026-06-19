-- Optional v8 admin policies.
-- Run this ONLY if the admin page cannot see/update redeem requests.
-- Replace the UUID with your admin user id if different.

create policy "Admin can view all redemption requests"
on public.redemption_requests
for select
using (auth.uid() = '6c4e7198-b08e-4e78-b4c7-f2abea9f5311');

create policy "Admin can update all redemption requests"
on public.redemption_requests
for update
using (auth.uid() = '6c4e7198-b08e-4e78-b4c7-f2abea9f5311');
