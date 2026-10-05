-- Make the intentional deny-by-default RLS posture explicit for test-control tables.
-- This preserves the existing behavior while documenting that browser/authenticated
-- clients must never access test-control state directly. Privileged server-side
-- paths continue to use their existing controlled roles.

create policy hms_test_runtime_deny_all
  on public.hms_test_runtime
  for all
  to anon, authenticated
  using (false)
  with check (false);

create policy hms_test_runtime_audit_deny_all
  on public.hms_test_runtime_audit
  for all
  to anon, authenticated
  using (false)
  with check (false);

create policy hms_test_users_deny_all
  on public.hms_test_users
  for all
  to anon, authenticated
  using (false)
  with check (false);
