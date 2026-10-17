-- Phase 8: preserve the legacy audit writer only on installations that have its table.
-- Canonical installations use public.patient_audit and the audit_patient_change()
-- trigger hardened by the preceding retention migration. Do not create a runtime
-- dependency on a legacy table that does not exist in a clean replay.
DO $patient_audit_trigger_hardening$
BEGIN
  IF to_regclass('public.patient_audit_log') IS NOT NULL THEN
    EXECUTE $legacy_function$
      CREATE OR REPLACE FUNCTION public.audit_patient_changes()
      RETURNS TRIGGER
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = ''
      AS $audit_patient_changes$
      DECLARE
        old_json JSONB;
        new_json JSONB;
        changed TEXT[] := '{}';
        key TEXT;
      BEGIN
        IF TG_OP = 'INSERT' THEN
          INSERT INTO public.patient_audit_log(patient_id, changed_by, action, new_record)
          VALUES (NEW.id, auth.uid(), TG_OP, to_jsonb(NEW));
          RETURN NEW;
        ELSIF TG_OP = 'DELETE' THEN
          INSERT INTO public.patient_audit_log(patient_id, changed_by, action, old_record)
          VALUES (NULL, auth.uid(), TG_OP, to_jsonb(OLD));
          RETURN OLD;
        END IF;

        old_json := to_jsonb(OLD);
        new_json := to_jsonb(NEW);

        FOR key IN SELECT jsonb_object_keys(new_json) LOOP
          IF old_json -> key IS DISTINCT FROM new_json -> key THEN
            changed := array_append(changed, key);
          END IF;
        END LOOP;

        IF cardinality(changed) > 0 THEN
          INSERT INTO public.patient_audit_log(
            patient_id, changed_by, action, old_record, new_record, changed_fields
          ) VALUES (
            NEW.id, auth.uid(), TG_OP, old_json, new_json, changed
          );
        END IF;

        RETURN NEW;
      END;
      $audit_patient_changes$;
    $legacy_function$;
    REVOKE ALL ON FUNCTION public.audit_patient_changes() FROM PUBLIC;
    REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated;
  ELSIF to_regclass('public.patient_audit') IS NOT NULL THEN
    -- Canonical audit trigger/function was hardened in
    -- 20260912002100_fix_patient_audit_delete_retention.sql.
    NULL;
  ELSE
    RAISE EXCEPTION 'Neither public.patient_audit nor public.patient_audit_log exists; refusing to skip audit hardening';
  END IF;
END;
$patient_audit_trigger_hardening$;
