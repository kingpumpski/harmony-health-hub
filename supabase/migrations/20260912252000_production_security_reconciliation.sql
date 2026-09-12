-- Production security reconciliation.
-- Keeps notification mutations user-scoped, narrows longitudinal clinical access,
-- and expands immutable audit coverage without changing existing workflow RPCs.

CREATE OR REPLACE FUNCTION public.mark_notification_read(_notification_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  changed BOOLEAN := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  UPDATE public.notifications
  SET is_read = true
  WHERE id = _notification_id
    AND is_read = false
    AND (
      recipient_user_id = auth.uid()
      OR (
        recipient_user_id IS NULL
        AND recipient_role IS NOT NULL
        AND (
          public.has_role(auth.uid(), recipient_role)
          OR (recipient_role = 'clinical' AND (
            public.has_role(auth.uid(),'practitioner') OR
            public.has_role(auth.uid(),'nurse') OR
            public.has_role(auth.uid(),'midwife') OR
            public.has_role(auth.uid(),'specialist_nurse')
          ))
        )
      )
    );

  changed := FOUND;
  RETURN changed;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notifications_read(_notification_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  changed INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  UPDATE public.notifications
  SET is_read = true
  WHERE id = ANY(COALESCE(_notification_ids, ARRAY[]::UUID[]))
    AND is_read = false
    AND (
      recipient_user_id = auth.uid()
      OR (
        recipient_user_id IS NULL
        AND recipient_role IS NOT NULL
        AND (
          public.has_role(auth.uid(), recipient_role)
          OR (recipient_role = 'clinical' AND (
            public.has_role(auth.uid(),'practitioner') OR
            public.has_role(auth.uid(),'nurse') OR
            public.has_role(auth.uid(),'midwife') OR
            public.has_role(auth.uid(),'specialist_nurse')
          ))
        )
      )
    );

  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_notification_read(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_notifications_read(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(UUID[]) TO authenticated;

-- Patient continuity contains clinical and financial information. Accounting and
-- front-desk roles use their dedicated operational modules instead of the full
-- longitudinal clinical record.
CREATE OR REPLACE FUNCTION public.get_patient_care_continuity(_patient_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid UUID := auth.uid();
  result JSONB;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin') OR
    public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR
    public.has_role(uid,'midwife') OR
    public.has_role(uid,'specialist_nurse') OR
    public.has_role(uid,'pharmacist') OR
    public.has_role(uid,'lab_technician')
  ) THEN
    RAISE EXCEPTION 'Clinical continuity access denied';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  SELECT jsonb_build_object(
    'referrals', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,destination,specialty,reason,urgency,status,appointment_date,created_at FROM public.patient_referrals WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r), '[]'::jsonb),
    'transitions', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,transition_type,status,destination,summary,follow_up_required,follow_up_date,created_at,completed_at FROM public.care_transitions WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r), '[]'::jsonb),
    'mar', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY COALESCE(r.administered_at,r.scheduled_at,r.created_at) DESC) FROM (SELECT id,medication_name,dose,route,status,scheduled_at,administered_at,reason,created_at FROM public.medication_administrations WHERE patient_id=_patient_id ORDER BY COALESCE(administered_at,scheduled_at,created_at) DESC LIMIT 100) r), '[]'::jsonb),
    'emergency', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.arrival_time DESC) FROM (SELECT id,chief_complaint,acuity,arrival_mode,status,arrival_time,created_at,disposition FROM public.emergency_cases WHERE patient_id=_patient_id ORDER BY arrival_time DESC LIMIT 100) r), '[]'::jsonb),
    'theatre', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.scheduled_start DESC) FROM (SELECT id,procedure_name,theatre_name,scheduled_start,urgency,status,anesthetist_id,created_at FROM public.theatre_cases WHERE patient_id=_patient_id ORDER BY scheduled_start DESC LIMIT 100) r), '[]'::jsonb),
    'transfusion', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,blood_product,unit_identifier,blood_group,status,started_at,completed_at,reaction_observed,reaction_notes,created_at FROM public.transfusion_records WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r), '[]'::jsonb),
    'claims', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM (SELECT id,payer_name,member_number,amount_claimed,amount_approved,amount_paid,status,service_from,service_to,rejection_reason,created_at FROM public.insurance_claims WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100) r), '[]'::jsonb),
    'admissions', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.admitted_at DESC) FROM (SELECT id,status,reason,admitted_at,discharged_at,discharge_summary FROM public.admissions WHERE patient_id=_patient_id ORDER BY admitted_at DESC LIMIT 100) r), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_patient_care_continuity(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_patient_care_continuity(UUID) TO authenticated;

-- Expand the existing clinical audit trigger to additional high-value domains.
DO $$
DECLARE
  table_name TEXT;
  trigger_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'dental_records',
    'procedure_notes',
    'emergency_cases',
    'theatre_cases',
    'transfusion_records',
    'nursing_care_plans',
    'nursing_shift_handovers',
    'ward_beds',
    'medication_administrations',
    'patient_referrals',
    'care_transitions'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL
       AND to_regprocedure('public.audit_clinical_record_change()') IS NOT NULL THEN
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

-- Notifications are user-facing and may contain sensitive operational context.
-- They remain readable only through existing RLS policies; mutation is RPC-only.
REVOKE INSERT, UPDATE, DELETE ON public.notifications FROM authenticated;
GRANT SELECT ON public.notifications TO authenticated;
