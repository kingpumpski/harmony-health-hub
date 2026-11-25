BEGIN;

SELECT plan(5);

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

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure
      AND p.prosecdef
      AND p.proconfig @> ARRAY['search_path=""']
  ),
  'billing materialization preserves SECURITY DEFINER and an empty search_path'
);

SELECT is(
  pg_get_function_result('public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure),
  'TABLE(invoice_id uuid, invoice_item_id uuid, source_type text, source_id uuid, description text, category text, department text, quantity integer, unit_price numeric, amount numeric, paid_amount numeric, outstanding_amount numeric, service_order_id uuid, service_order_status text)',
  'billing materialization retains its canonical return shape'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE')
  AND NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
    WHERE p.oid = 'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure
      AND a.grantee = 0
      AND a.privilege_type = 'EXECUTE'
  ),
  'billing materialization remains authenticated-only with no PUBLIC or anon execution'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_proc p
    WHERE p.oid = 'public.prepare_patient_billable_items(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure
      AND p.pronargs = 3
      AND p.proargtypes = '2950 1184 1184'::oidvector
  ),
  'billing materialization retains its three-argument UUID/timestamptz signature'
);

SELECT * FROM finish();
ROLLBACK;
