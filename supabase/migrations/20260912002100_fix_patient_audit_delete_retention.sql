-- Keep the immutable audit snapshot when a patient is deleted.
-- The retention migration makes patient_audit.patient_id nullable and uses ON DELETE SET NULL.
-- A DELETE trigger must write NULL itself because the parent row is already being removed.
CREATE OR REPLACE FUNCTION public.audit_patient_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $audit_patient_change$
DECLARE
  old_json JSONB;
  new_json JSONB;
  changed JSONB;
BEGIN
  old_json := CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END;
  new_json := CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END;

  IF TG_OP = 'UPDATE' THEN
    SELECT COALESCE(
      jsonb_object_agg(
        COALESCE(o.key, n.key),
        jsonb_build_object('old', o.value, 'new', n.value)
      ) FILTER (WHERE o.value IS DISTINCT FROM n.value),
      '{}'::jsonb
    )
    INTO changed
    FROM jsonb_each(old_json) AS o
    FULL JOIN jsonb_each(new_json) AS n ON n.key = o.key;
  ELSE
    changed := '{}'::jsonb;
  END IF;

  INSERT INTO public.patient_audit (
    patient_id, actor_user_id, operation, changed_fields, old_record, new_record
  ) VALUES (
    CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE NEW.id END,
    auth.uid(),
    TG_OP,
    changed,
    old_json,
    new_json
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$audit_patient_change$;

REVOKE ALL ON FUNCTION public.audit_patient_change() FROM PUBLIC;
