-- Restore the patient audit log before retention and trigger-hardening migrations use it.
-- This is the application-facing audit table queried by PatientAudit.tsx and later RLS/index migrations.
CREATE TABLE IF NOT EXISTS public.patient_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  old_record JSONB,
  new_record JSONB,
  changed_fields TEXT[] NOT NULL DEFAULT '{}'
);

ALTER TABLE public.patient_audit_log ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.patient_audit_log FROM authenticated, anon;

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
$audit_patient_changes$;

DROP TRIGGER IF EXISTS t_patient_audit_changes ON public.patients;
CREATE TRIGGER t_patient_audit_changes
AFTER INSERT OR UPDATE OR DELETE ON public.patients
FOR EACH ROW EXECUTE FUNCTION public.audit_patient_changes();
