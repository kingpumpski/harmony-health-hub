-- Consolidate any legacy patient_audit_log rows into the canonical patient_audit store.
-- Preserve IDs and all available audit payload fields; keep the old table as a read-disabled archive.
DO $legacy_patient_audit_consolidation$
DECLARE
  trigger_row record;
BEGIN
  IF to_regclass('public.patient_audit_log') IS NOT NULL THEN
    IF to_regclass('public.patient_audit') IS NULL THEN
      RAISE EXCEPTION 'Legacy patient_audit_log exists but canonical public.patient_audit is missing';
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='patient_audit_log' AND column_name='changed_by'
    ) OR NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='patient_audit_log' AND column_name='changed_at'
    ) OR NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='patient_audit_log' AND column_name='changed_fields'
    ) THEN
      RAISE EXCEPTION 'Legacy patient_audit_log has an unsupported shape; stop for explicit reconciliation';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.patient_audit_log l
      JOIN public.patient_audit c ON c.id = l.id
      WHERE c.patient_id IS DISTINCT FROM l.patient_id
         OR c.actor_user_id IS DISTINCT FROM l.changed_by
         OR c.operation IS DISTINCT FROM l.action
         OR c.old_record IS DISTINCT FROM l.old_record
         OR c.new_record IS DISTINCT FROM l.new_record
         OR c.occurred_at IS DISTINCT FROM l.changed_at
    ) THEN
      RAISE EXCEPTION 'Patient audit IDs conflict across legacy and canonical stores; refusing to overwrite either audit record';
    END IF;

    INSERT INTO public.patient_audit
      (id, patient_id, actor_user_id, operation, changed_fields, old_record, new_record, occurred_at)
    SELECT l.id, l.patient_id, l.changed_by, l.action,
           COALESCE(to_jsonb(l.changed_fields), '[]'::jsonb),
           l.old_record, l.new_record, l.changed_at
    FROM public.patient_audit_log l
    ON CONFLICT (id) DO NOTHING;

    IF EXISTS (
      SELECT 1 FROM public.patient_audit_log l
      LEFT JOIN public.patient_audit c ON c.id=l.id
      WHERE c.id IS NULL
    ) THEN
      RAISE EXCEPTION 'Patient audit consolidation did not copy every legacy audit ID';
    END IF;

    IF to_regprocedure('public.audit_patient_changes()') IS NOT NULL THEN
      FOR trigger_row IN
        SELECT t.tgname, t.tgrelid::regclass AS table_name
        FROM pg_trigger t
        WHERE t.tgfoid = to_regprocedure('public.audit_patient_changes()')
          AND NOT t.tgisinternal
      LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %s', trigger_row.tgname, trigger_row.table_name);
      END LOOP;
      EXECUTE 'DROP FUNCTION public.audit_patient_changes()';
    END IF;

    EXECUTE 'ALTER TABLE public.patient_audit_log ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.patient_audit_log FROM PUBLIC, anon, authenticated';
    EXECUTE 'COMMENT ON TABLE public.patient_audit_log IS ''Legacy archive; active patient audit writes use public.patient_audit.''';
  END IF;
END
$legacy_patient_audit_consolidation$;
