-- Complete the inpatient discharge -> Accounts handoff without changing the existing
-- billing calculation path. The discharge RPC remains the server authority and
-- emits one actionable Accounts notification after a successful state transition.
CREATE OR REPLACE FUNCTION public.discharge_admission_workflow(_admission_id UUID, _summary TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_id UUID;
  v_patient_id UUID;
  v_patient_name TEXT;
  v_patient_code TEXT;
  v_discharged_at TIMESTAMPTZ;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN
    RAISE EXCEPTION 'Admission discharge is not permitted';
  END IF;

  UPDATE admissions
  SET status='discharged', discharged_at=now(), discharge_summary=COALESCE(NULLIF(btrim(_summary),''),'Discharged from inpatient admission.')
  WHERE id=_admission_id AND status='admitted'
  RETURNING id, patient_id, discharged_at INTO v_id, v_patient_id, v_discharged_at;

  IF v_id IS NULL THEN RAISE EXCEPTION 'Admission not found or is no longer active'; END IF;

  SELECT concat_ws(' ', first_name, last_name), patient_code
  INTO v_patient_name, v_patient_code
  FROM patients WHERE id=v_patient_id;

  INSERT INTO notifications(
    recipient_role, title, message, severity, category, link,
    related_patient_id, related_entity_id, metadata
  ) VALUES (
    'accountant',
    'Discharged patient ready for billing reconciliation',
    format('%s (%s) has been discharged. Reconcile the complete patient bill, including inpatient services, before settlement.', COALESCE(v_patient_name,'Patient'), COALESCE(v_patient_code,'no patient code')),
    'warning',
    'payment',
    '/billing',
    v_patient_id,
    v_id,
    jsonb_build_object('workflow','discharge_billing_handoff','admission_id',v_id,'discharged_at',v_discharged_at)
  );

  RETURN jsonb_build_object('admission_id',v_id,'patient_id',v_patient_id,'status','discharged','billing_handoff','pending');
END; $$;

REVOKE ALL ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.discharge_admission_workflow(UUID,TEXT) TO authenticated;
