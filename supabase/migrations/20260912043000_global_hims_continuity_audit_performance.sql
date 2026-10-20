-- Global HIMS continuity hardening.
-- Adds patient-scoped indexes and auditable maternity/facility changes.
-- The continuity RPC is reconciled here with the canonical global HIMS schema so
-- a clean migration run never compiles against retired column names.

-- These indexes are applied only when the legacy table and all indexed columns exist.
DO $$
DECLARE
  v_index record;
  v_relation regclass;
BEGIN
  FOR v_index IN
    SELECT * FROM (VALUES
      ('idx_patient_referrals_patient_created', 'patient_referrals', ARRAY['patient_id', 'created_at']::text[], 'patient_id, created_at DESC'),
      ('idx_care_transitions_patient_created', 'care_transitions', ARRAY['patient_id', 'created_at']::text[], 'patient_id, created_at DESC'),
      ('idx_medication_administrations_patient_scheduled', 'medication_administrations', ARRAY['patient_id', 'scheduled_at']::text[], 'patient_id, scheduled_at DESC'),
      ('idx_emergency_cases_patient_created', 'emergency_cases', ARRAY['patient_id', 'created_at']::text[], 'patient_id, created_at DESC'),
      ('idx_theatre_cases_patient_scheduled', 'theatre_cases', ARRAY['patient_id', 'scheduled_start']::text[], 'patient_id, scheduled_start DESC'),
      ('idx_transfusion_records_patient_created', 'transfusion_records', ARRAY['patient_id', 'created_at']::text[], 'patient_id, created_at DESC'),
      ('idx_insurance_claims_patient_created', 'insurance_claims', ARRAY['patient_id', 'created_at']::text[], 'patient_id, created_at DESC'),
      ('idx_admissions_patient_admitted', 'admissions', ARRAY['patient_id', 'admitted_at']::text[], 'patient_id, admitted_at DESC'),
      ('idx_service_orders_patient_created', 'service_orders', ARRAY['patient_id', 'created_at']::text[], 'patient_id, created_at DESC')
    ) AS requested(index_name, table_name, columns_to_check, index_columns)
  LOOP
    v_relation := to_regclass(format('public.%I', v_index.table_name));
    IF v_relation IS NOT NULL
       AND NOT EXISTS (
         SELECT 1
         FROM unnest(v_index.columns_to_check) AS required(column_name)
         WHERE NOT EXISTS (
           SELECT 1
           FROM pg_attribute
           WHERE attrelid = v_relation
             AND attname = required.column_name
             AND attnum > 0
             AND NOT attisdropped
         )
       ) THEN
      EXECUTE format(
        'CREATE INDEX IF NOT EXISTS %I ON public.%I (%s)',
        v_index.index_name,
        v_index.table_name,
        v_index.index_columns
      );
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_global_hims_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_entity UUID;
  v_action TEXT;
  v_severity TEXT := 'info';
  v_metadata JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN v_entity := OLD.id; ELSE v_entity := NEW.id; END IF;
  v_action := lower(TG_OP) || '_record';
  IF TG_TABLE_NAME = 'facility_configuration' AND TG_OP = 'UPDATE' THEN
    v_action := 'update_facility_configuration';
  ELSIF TG_TABLE_NAME LIKE 'maternity_%' THEN
    v_action := lower(TG_OP) || '_maternity_' || replace(TG_TABLE_NAME, 'maternity_', '');
  END IF;
  IF TG_TABLE_NAME = 'maternity_episodes' AND TG_OP <> 'DELETE' AND COALESCE(to_jsonb(NEW)->>'risk_level', 'routine') = 'critical' THEN
    v_severity := 'critical';
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
$$;

DROP TRIGGER IF EXISTS t_facility_configuration_audit ON public.facility_configuration;
CREATE TRIGGER t_facility_configuration_audit AFTER INSERT OR UPDATE OR DELETE ON public.facility_configuration FOR EACH ROW EXECUTE FUNCTION public.audit_global_hims_change();
DROP TRIGGER IF EXISTS t_maternity_episode_audit ON public.maternity_episodes;
CREATE TRIGGER t_maternity_episode_audit AFTER INSERT OR UPDATE OR DELETE ON public.maternity_episodes FOR EACH ROW EXECUTE FUNCTION public.audit_global_hims_change();
DROP TRIGGER IF EXISTS t_maternity_observation_audit ON public.maternity_observations;
CREATE TRIGGER t_maternity_observation_audit AFTER INSERT OR UPDATE OR DELETE ON public.maternity_observations FOR EACH ROW EXECUTE FUNCTION public.audit_global_hims_change();

CREATE OR REPLACE FUNCTION public.get_patient_care_continuity(_patient_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT jsonb_build_object(
    'referrals', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,destination,specialty,reason,urgency,status,appointment_date,created_at FROM public.patient_referrals WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'transitions', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,transition_type,status,destination,summary,follow_up_required,follow_up_date,created_at,completed_at FROM public.care_transitions WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'mar', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.scheduled_at DESC) FROM (SELECT id,medication_name,dose,route,status,scheduled_at,administered_at,reason FROM public.medication_administrations WHERE patient_id=_patient_id ORDER BY scheduled_at DESC LIMIT 100) r),'[]'::jsonb),
    'emergency', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.arrival_time DESC) FROM (SELECT id,chief_complaint,acuity,arrival_mode,status,arrival_time,created_at,disposition FROM public.emergency_cases WHERE patient_id=_patient_id ORDER BY arrival_time DESC LIMIT 100) r),'[]'::jsonb),
    'theatre', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.scheduled_start DESC) FROM (SELECT id,procedure_name,theatre_name,scheduled_start,urgency,status,anesthetist_id,created_at FROM public.theatre_cases WHERE patient_id=_patient_id ORDER BY scheduled_start DESC LIMIT 100) r),'[]'::jsonb),
    'transfusion', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,blood_product,unit_identifier,blood_group,status,started_at,completed_at,reaction_observed,reaction_notes,created_at FROM public.transfusion_records WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object('rejection_reason', to_jsonb(r)->>'rejection_reason') ORDER BY r.created_at DESC) FROM (SELECT * FROM public.insurance_claims WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r),'[]'::jsonb),
    'admissions', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.admitted_at DESC) FROM (SELECT id,status,reason,admitted_at,discharged_at,discharge_summary FROM public.admissions WHERE patient_id=_patient_id ORDER BY admitted_at DESC LIMIT 100) r),'[]'::jsonb)
  );
$$;
GRANT EXECUTE ON FUNCTION public.get_patient_care_continuity(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_patient_care_continuity(UUID) FROM PUBLIC;
