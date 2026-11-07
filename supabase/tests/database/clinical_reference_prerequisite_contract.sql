DO $$
DECLARE
  table_name text;
  table_names text[] := ARRAY[
    'ai_diagnosis_suggestions',
    'ai_symptom_icd_map',
    'audit_logs',
    'lab_tests',
    'sync_queue'
  ];
BEGIN
  FOREACH table_name IN ARRAY table_names LOOP
    ASSERT to_regclass('public.' || table_name) IS NOT NULL,
      table_name || ' missing from the canonical clinical reference schema';
    ASSERT EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = table_name
        AND c.relrowsecurity
    ), table_name || ' must have RLS enabled';
    ASSERT EXISTS (
      SELECT 1
      FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = table_name
    ), table_name || ' must have an explicit RLS policy';
    ASSERT NOT EXISTS (
      SELECT 1
      FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = table_name
        AND ('anon' = ANY(p.roles) OR 'public' = ANY(p.roles))
    ), 'anon/public policies must not expose ' || table_name;
    ASSERT has_table_privilege('service_role', 'public.' || table_name, 'SELECT'),
      'service_role must retain access to ' || table_name;
  END LOOP;

  ASSERT has_table_privilege('authenticated', 'public.ai_diagnosis_suggestions', 'INSERT'),
    'clinical users need the table privilege before the clinical-staff RLS policy can authorize diagnosis writes';
  ASSERT has_table_privilege('authenticated', 'public.ai_diagnosis_suggestions', 'UPDATE'),
    'clinical users need the update privilege before the clinical-staff RLS policy can authorize diagnosis updates';
  ASSERT has_table_privilege('authenticated', 'public.ai_symptom_icd_map', 'INSERT'),
    'authenticated role needs table-level insert privilege; RLS limits it to admins';
  ASSERT has_table_privilege('authenticated', 'public.ai_symptom_icd_map', 'UPDATE'),
    'authenticated role needs table-level update privilege; RLS limits it to admins';
  ASSERT has_table_privilege('authenticated', 'public.lab_tests', 'INSERT'),
    'authenticated role needs table-level insert privilege; RLS limits it to admins';
  ASSERT has_table_privilege('authenticated', 'public.lab_tests', 'UPDATE'),
    'authenticated role needs table-level update privilege; RLS limits it to admins';
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_policies p
    WHERE p.schemaname='public' AND p.tablename='audit_logs'
      AND p.cmd IN ('INSERT','UPDATE','DELETE','ALL')
      AND 'authenticated' = ANY(p.roles)
  ), 'authenticated users must not have a direct audit_logs write policy';
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_policies p
    WHERE p.schemaname='public' AND p.tablename='sync_queue'
      AND p.cmd IN ('INSERT','UPDATE','DELETE','ALL')
      AND 'authenticated' = ANY(p.roles)
  ), 'authenticated users must not have a direct sync_queue write policy';

  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='ai_diagnosis_suggestions'
      AND policyname='clinical staff manage ai diagnosis suggestions'
  ), 'clinical diagnosis suggestion RLS policy missing';
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='audit_logs'
      AND policyname='admins read audit logs'
  ), 'audit log admin read policy missing';
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='sync_queue'
      AND policyname='admins read sync queue'
  ), 'sync queue admin read policy missing';
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='ai_symptom_icd_map'
      AND policyname LIKE 'admins_write_symptom_map%'
  ), 'symptom map admin write policies missing';
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='lab_tests'
      AND policyname LIKE 'lab_tests_%'
  ), 'lab test admin write policies missing';
END $$;
