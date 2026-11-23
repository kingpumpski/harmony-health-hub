-- Restore the least-privilege boundary established by the original
-- laboratory panel migration. The application accesses these tables only
-- through the audited SECURITY DEFINER RPCs, not direct PostgREST table access.
REVOKE ALL PRIVILEGES ON TABLE
  public.lab_test_groups,
  public.lab_test_group_items
FROM PUBLIC, anon, authenticated;

-- Pin the trigger helper's lookup path. pg_catalog remains implicitly
-- available, and the trigger body only calls now() and accesses NEW.
ALTER FUNCTION public.ensure_updated_at()
  SET search_path = '';

