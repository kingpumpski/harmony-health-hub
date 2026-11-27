BEGIN;

SELECT plan(8);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid='public.patient_audit'::regclass)
  AND (SELECT relrowsecurity FROM pg_class WHERE oid='public.patient_audit_log'::regclass),
  'both patient audit tables retain row-level security'
);

SELECT ok(
  NOT has_table_privilege('anon','public.patient_audit','SELECT')
  AND NOT has_table_privilege('anon','public.patient_audit','INSERT')
  AND NOT has_table_privilege('anon','public.patient_audit','UPDATE')
  AND NOT has_table_privilege('anon','public.patient_audit','DELETE')
  AND NOT has_table_privilege('anon','public.patient_audit_log','SELECT')
  AND NOT has_table_privilege('anon','public.patient_audit_log','INSERT')
  AND NOT has_table_privilege('anon','public.patient_audit_log','UPDATE')
  AND NOT has_table_privilege('anon','public.patient_audit_log','DELETE'),
  'anonymous role has no direct privileges on either patient audit table'
);

SELECT ok(
  NOT has_table_privilege('authenticated','public.patient_audit','SELECT')
  AND NOT has_table_privilege('authenticated','public.patient_audit','INSERT')
  AND NOT has_table_privilege('authenticated','public.patient_audit','UPDATE')
  AND NOT has_table_privilege('authenticated','public.patient_audit','DELETE')
  AND has_table_privilege('authenticated','public.patient_audit_log','SELECT')
  AND NOT has_table_privilege('authenticated','public.patient_audit_log','INSERT')
  AND NOT has_table_privilege('authenticated','public.patient_audit_log','UPDATE')
  AND NOT has_table_privilege('authenticated','public.patient_audit_log','DELETE'),
  'authenticated clients can read only the facility-scoped audit log and cannot read or mutate the legacy snapshot table'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid='public.patient_audit_log'::regclass
      AND polcmd='r'
      AND polname='patient_audit_log_active_facility_read'
      AND pg_get_expr(polqual,polrelid) ILIKE '%current_user_facility_id%'
      AND pg_get_expr(polqual,polrelid) ILIKE '%patients%'
      AND pg_get_expr(polqual,polrelid) ILIKE '%patient_id%'
      AND pg_get_expr(polqual,polrelid) ILIKE '%exists%'
  ),
  'patient_audit_log reads require a patient row in the caller active facility'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid='public.patient_audit_log'::regclass
      AND polcmd='r'
      AND pg_get_expr(polqual,polrelid) ILIKE '%current_user_is_clinical_staff()%'
      AND pg_get_expr(polqual,polrelid) NOT ILIKE '%facility%'
  ),
  'patient_audit_log has no broad clinical-staff-only read policy'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid='public.patient_audit_log'::regclass
      AND polcmd='r'
      AND pg_get_expr(polqual,polrelid) NOT ILIKE '%patient_id%'
  ),
  'orphan audit rows without patient lineage are not exposed by a read policy'
);

SELECT ok(
  (SELECT count(*) FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('audit_patient_changes','audit_patient_change')
     AND p.prosecdef
     AND COALESCE(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
     AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
     AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')) = 2,
  'patient audit trigger functions are SECURITY DEFINER, pinned to an empty search_path and not client-callable'
);

SELECT ok(
  (SELECT pg_get_functiondef('public.audit_patient_changes()'::regprocedure) ILIKE '%old_record, new_record, changed_fields%'
     AND pg_get_functiondef('public.audit_patient_changes()'::regprocedure) ILIKE '%NULL,%'
     AND pg_get_functiondef('public.audit_patient_change()'::regprocedure) ILIKE '%changed_fields, old_record, new_record%'
     AND pg_get_functiondef('public.audit_patient_change()'::regprocedure) ILIKE '%NULL,%'),
  'future patient audit events retain changed-field names without persisting full old/new row snapshots'
);

SELECT * FROM finish();
ROLLBACK;
