-- Repair the polymorphic audit trigger: NEW has a different row shape for each
-- attached table, so maternity-only fields must be accessed in a nested IF.
CREATE OR REPLACE FUNCTION public.audit_global_hims_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $global_hims_audit$
DECLARE
  v_actor UUID := auth.uid();
  v_entity UUID;
  v_action TEXT;
  v_severity TEXT := 'info';
  v_metadata JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_entity := OLD.id;
  ELSE
    v_entity := NEW.id;
  END IF;

  v_action := lower(TG_OP) || '_record';
  IF TG_TABLE_NAME = 'facility_configuration' AND TG_OP = 'UPDATE' THEN
    v_action := 'update_facility_configuration';
  ELSIF TG_TABLE_NAME LIKE 'maternity_%' THEN
    v_action := lower(TG_OP) || '_maternity_' || replace(TG_TABLE_NAME, 'maternity_', '');
  END IF;

  IF TG_TABLE_NAME = 'maternity_episodes' AND TG_OP <> 'DELETE' THEN
    IF COALESCE(NEW.risk_level, 'routine') = 'critical' THEN
      v_severity := 'critical';
    END IF;
  END IF;

  v_metadata := jsonb_build_object(
    'table_name', TG_TABLE_NAME,
    'operation', TG_OP,
    'old_record', CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
    'new_record', CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END
  );

  IF v_actor IS NOT NULL THEN
    INSERT INTO public.system_audit_log(actor_id, action, module, entity_type, entity_id, severity, metadata)
    VALUES (v_actor, v_action, 'global_hims', TG_TABLE_NAME, v_entity, v_severity, v_metadata);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$global_hims_audit$;
