-- Phase 8: keep patient auditing functional after application-level audit writes are revoked.
-- The trigger is SECURITY DEFINER and explicitly owns the append path.

CREATE OR REPLACE FUNCTION public.audit_patient_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    VALUES (OLD.id, auth.uid(), TG_OP, to_jsonb(OLD));
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
$$;

REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated;
