-- Compatibility/reconciliation layer for clinical module workflows.
-- Secure transition RPCs are preferred by clients; legacy authenticated reads remain intact.

CREATE OR REPLACE FUNCTION public.attach_lab_catalogue_to_order(_lab_order_id UUID, _catalogue_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_catalog public.lab_test_catalogue%ROWTYPE;
BEGIN
  IF NOT (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'admin')) THEN
    RAISE EXCEPTION 'Clinical staff access required';
  END IF;
  SELECT * INTO v_catalog FROM public.lab_test_catalogue WHERE id = _catalogue_id AND active = true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active laboratory catalogue item not found'; END IF;
  UPDATE public.lab_orders
  SET lab_test_catalogue_id = _catalogue_id,
      test_name = v_catalog.test_name,
      test_category = v_catalog.category
  WHERE id = _lab_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  RETURN jsonb_build_object('lab_order_id',_lab_order_id,'catalogue_id',_catalogue_id,'test_name',v_catalog.test_name);
END;
$$;

REVOKE ALL ON FUNCTION public.attach_lab_catalogue_to_order(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.attach_lab_catalogue_to_order(UUID) TO authenticated;

-- Ensure the transition functions cannot be invoked anonymously.
REVOKE EXECUTE ON FUNCTION public.collect_lab_sample(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION public.approve_lab_result(UUID) FROM anon;

-- Operational indexes used by queues, billing gates and patient-centric views.
CREATE INDEX IF NOT EXISTS idx_lab_orders_patient_status_created ON public.lab_orders(patient_id,status,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_service_orders_related_department_status ON public.service_orders(related_entity_id,department,status);
CREATE INDEX IF NOT EXISTS idx_appointments_patient_scheduled ON public.appointments(patient_id,scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_encounters_patient_created ON public.encounters(patient_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prescriptions_patient_created ON public.prescriptions(patient_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admissions_patient_admitted ON public.admissions(patient_id,admitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_insurance_claims_patient_created ON public.insurance_claims(patient_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_emergency_cases_patient_created ON public.emergency_cases(patient_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_theatre_cases_patient_scheduled ON public.theatre_cases(patient_id,scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_transfusion_records_patient_created ON public.transfusion_records(patient_id,created_at DESC);

-- Keep the audit trail queryable for the Patient Hub and administrative review.
CREATE INDEX IF NOT EXISTS idx_patient_audit_changed_by_time ON public.patient_audit_log(changed_by,changed_at DESC);
