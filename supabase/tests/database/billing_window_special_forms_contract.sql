BEGIN;

SELECT plan(1);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure
      AND pg_get_functiondef(p.oid) NOT ILIKE '%pg_catalog.coalesce(%'
      AND pg_get_functiondef(p.oid) NOT ILIKE '%pg_catalog.greatest(%'
      AND pg_get_functiondef(p.oid) NOT ILIKE '%pg_catalog.least(%'
  ),
  'billing materialization function contains no schema-qualified SQL special forms'
);

SELECT * FROM finish();
ROLLBACK;
