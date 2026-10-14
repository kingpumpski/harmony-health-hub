-- Make the no-direct-client-access posture for laboratory specimens explicit in RLS.
-- Clinical specimen access continues only through authorized, facility-scoped RPCs.
BEGIN;

ALTER TABLE public.lab_specimens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_specimens FROM PUBLIC, anon, authenticated;

DO $policy$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'lab_specimens'
      AND policyname = 'lab_specimens_deny_direct_client_access'
  ) THEN
    CREATE POLICY lab_specimens_deny_direct_client_access
      ON public.lab_specimens
      FOR ALL
      TO anon, authenticated
      USING (false)
      WITH CHECK (false);
  END IF;
END;
$policy$;

COMMIT;