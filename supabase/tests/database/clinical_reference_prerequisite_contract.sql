DO $$
DECLARE
  table_name text;
  expected_column record;
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

  FOR expected_column IN
    SELECT * FROM (VALUES
      ('ai_diagnosis_suggestions','id','uuid','NO'),
      ('ai_diagnosis_suggestions','encounter_id','uuid','YES'),
      ('ai_diagnosis_suggestions','suggested_icd','text','YES'),
      ('ai_diagnosis_suggestions','reasoning','text','YES'),
      ('ai_diagnosis_suggestions','model_version','text','YES'),
      ('ai_diagnosis_suggestions','accepted','boolean','YES'),
      ('ai_diagnosis_suggestions','created_at','timestamp with time zone','YES'),
      ('ai_symptom_icd_map','id','uuid','NO'),
      ('ai_symptom_icd_map','confidence','numeric','YES'),
      ('ai_symptom_icd_map','created_at','timestamp with time zone','YES'),
      ('ai_symptom_icd_map','icd_code','text','YES'),
      ('ai_symptom_icd_map','symptom','text','NO'),
      ('audit_logs','id','uuid','NO'),
      ('audit_logs','action','text','YES'),
      ('audit_logs','created_at','timestamp with time zone','YES'),
      ('audit_logs','new_data','jsonb','YES'),
      ('audit_logs','old_data','jsonb','YES'),
      ('audit_logs','record_id','text','YES'),
      ('audit_logs','table_name','text','YES'),
      ('audit_logs','user_id','uuid','YES'),
      ('sync_queue','id','uuid','NO'),
      ('sync_queue','payload','jsonb','YES'),
      ('sync_queue','synced','boolean','YES'),
      ('sync_queue','table_name','text','YES'),
      ('lab_tests','id','uuid','NO'),
      ('lab_tests','loinc_code','text','YES'),
      ('lab_tests','normal_range','text','YES'),
      ('lab_tests','specimen','text','YES'),
      ('lab_tests','test_name','text','YES'),
      ('lab_tests','created_at','timestamp with time zone','YES')
    ) AS expected(table_name, column_name, data_type, is_nullable)
  LOOP
    ASSERT EXISTS (
      SELECT 1
      FROM information_schema.columns c
      WHERE c.table_schema = 'public'
        AND c.table_name = expected_column.table_name
        AND c.column_name = expected_column.column_name
        AND c.data_type = expected_column.data_type
        AND c.is_nullable = expected_column.is_nullable
    ), 'Schema/type/nullability mismatch for ' || expected_column.table_name || '.' || expected_column.column_name;
  END LOOP;

  ASSERT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class source_table ON source_table.oid = c.conrelid
    JOIN pg_namespace source_schema ON source_schema.oid = source_table.relnamespace
    JOIN pg_class target_table ON target_table.oid = c.confrelid
    JOIN pg_namespace target_schema ON target_schema.oid = target_table.relnamespace
    WHERE c.contype = 'f'
      AND source_schema.nspname = 'public'
      AND source_table.relname = 'ai_diagnosis_suggestions'
      AND target_schema.nspname = 'public'
      AND target_table.relname = 'encounters'
  ), 'AI diagnosis suggestions must retain the encounter foreign key';
  ASSERT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class source_table ON source_table.oid = c.conrelid
    JOIN pg_namespace source_schema ON source_schema.oid = source_table.relnamespace
    JOIN pg_class target_table ON target_table.oid = c.confrelid
    JOIN pg_namespace target_schema ON target_schema.oid = target_table.relnamespace
    WHERE c.contype = 'f'
      AND source_schema.nspname = 'public'
      AND source_table.relname = 'ai_diagnosis_suggestions'
      AND target_schema.nspname = 'public'
      AND target_table.relname = 'icd_codes'
  ), 'AI diagnosis suggestions must retain the ICD foreign key';
  ASSERT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class source_table ON source_table.oid = c.conrelid
    JOIN pg_namespace source_schema ON source_schema.oid = source_table.relnamespace
    JOIN pg_class target_table ON target_table.oid = c.confrelid
    JOIN pg_namespace target_schema ON target_schema.oid = target_table.relnamespace
    WHERE c.contype = 'f'
      AND source_schema.nspname = 'public'
      AND source_table.relname = 'ai_symptom_icd_map'
      AND target_schema.nspname = 'public'
      AND target_table.relname = 'icd_codes'
  ), 'Symptom-to-ICD map must retain the ICD foreign key';

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
