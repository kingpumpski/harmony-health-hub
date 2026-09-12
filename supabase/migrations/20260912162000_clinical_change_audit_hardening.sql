-- Clinical change audit hardening.
-- Additive and idempotent: preserve existing clinical workflows while ensuring
-- high-value clinical record changes are traceable through the existing system audit log.

CREATE OR REPLACE FUNCTION public.audit_clinical_record_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  entity_id UUID;
  event_name TEXT;
BEGIN
  entity_id := COALESCE(NEW.id, OLD.id);
  event_name := lower(TG_TABLE_NAME || '_' || TG_OP);

  PERFORM public.record_system_audit(
    event_name,
    'clinical',
    TG_TABLE_NAME,
    entity_id,
    CASE WHEN TG_OP = 'DELETE' THEN 'warning' ELSE 'info' END,
    jsonb_build_object(
      'operation', TG_OP,
      'table', TG_TABLE_NAME,
      'record_id', entity_id,
      'actor_id', auth.uid(),
      'old', CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
      'new', CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END
    )
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

DO $$
DECLARE
  table_name TEXT;
  trigger_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'encounters',
    'diagnoses',
    'prescriptions',
    'triage_assessments',
    'lab_test_catalogue',
    'insurance_claims'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL THEN
      trigger_name := 'trg_audit_' || table_name || '_changes';
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', trigger_name, table_name);
      EXECUTE format(
        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_record_change()',
        trigger_name,
        table_name
      );
    END IF;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.audit_clinical_record_change() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.audit_clinical_record_change() TO authenticated;
