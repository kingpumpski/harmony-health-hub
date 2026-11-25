BEGIN;

SELECT plan(6);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid='public.patient_audit'::regclass)
  AND (SELECT relrowsecurity FROM pg_class WHERE oid='public.patient_audit_log'::regclass),
  'both patient audit tables retain row-level security'
);

SELECT ok(
  NOT has_table_privilege('anon','public.patient_audit','SELECT')
  AND NOT has_table_privilege('anon','public.patient_audit_log','SELECT'),
  'anonymous role cannot directly read either patient audit table'
);

SELECT ok(
  NOT has_table_privilege('authenticated','public.patient_audit','INSERT')
  AND NOT has_table_privilege('authenticated','public.patient_audit','UPDATE')
  AND NOT has_table_privilege('authenticated','public.patient_audit','DELETE')
  AND NOT has_table_privilege('authenticated','public.patient_audit_log','INSERT')
  AND NOT has_table_privilege('authenticated','public.patient_audit_log','UPDATE')
  AND NOT has_table_privilege('authenticated','public.patient_audit_log','DELETE'),
  'authenticated clients cannot directly mutate patient audit records'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid='public.patient_audit'::regclass
      AND polcmd='r'
      AND polname='admins read patient audit'
      AND pg_get_expr(polqual,polrelid) ILIKE '%current_user_has_role%'
  ),
  'patient_audit reads remain admin-policy controlled'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid='public.patient_audit_log'::regclass
      AND polcmd='r'
      AND (
        pg_get_expr(polqual,polrelid) ILIKE '%current_user_can_select_facility_record%'
        OR pg_get_expr(polqual,polrelid) ILIKE '%current_user_facility_id%'
      )
  ),
  'patient_audit_log staff reads enforce facility context'
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

SELECT * FROM finish();
ROLLBACK;
