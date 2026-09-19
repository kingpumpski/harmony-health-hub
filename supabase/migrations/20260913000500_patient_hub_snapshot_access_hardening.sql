-- Tighten the Patient Hub snapshot boundary before it is consumed by the UI.
CREATE OR REPLACE FUNCTION public.get_patient_hub_snapshot(_patient_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  can_view BOOLEAN;
  is_clinical BOOLEAN;
  is_billing BOOLEAN;
  is_front_desk BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  can_view :=
    public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'practitioner') OR
    public.has_role(auth.uid(), 'nurse') OR public.has_role(auth.uid(), 'midwife') OR
    public.has_role(auth.uid(), 'specialist_nurse') OR public.has_role(auth.uid(), 'pharmacist') OR
    public.has_role(auth.uid(), 'lab_technician') OR public.has_role(auth.uid(), 'accountant') OR
    public.has_role(auth.uid(), 'front_desk');

  IF NOT can_view THEN RAISE EXCEPTION 'Patient Hub access is not permitted for this role'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient does not exist'; END IF;

  is_clinical := public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'practitioner') OR
    public.has_role(auth.uid(), 'nurse') OR public.has_role(auth.uid(), 'midwife') OR
    public.has_role(auth.uid(), 'specialist_nurse') OR public.has_role(auth.uid(), 'pharmacist') OR
    public.has_role(auth.uid(), 'lab_technician');
  is_billing := public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'accountant');
  is_front_desk := public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'front_desk');

  SELECT jsonb_build_object(
    'patient', CASE
      WHEN is_clinical THEN to_jsonb(p)
      ELSE jsonb_build_object(
        'id', p.id,
        'patient_code', p.patient_code,
        'first_name', p.first_name,
        'last_name', p.last_name,
        'date_of_birth', p.date_of_birth,
        'sex', p.sex,
        'phone', p.phone,
        'email', p.email,
        'address', p.address,
        'status', p.status
      )
    END,
    'appointments', CASE WHEN is_clinical OR is_front_desk THEN COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.scheduled_at DESC) FROM public.appointments a WHERE a.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END,
    'vitals', CASE WHEN is_clinical THEN COALESCE((SELECT jsonb_agg(to_jsonb(v) ORDER BY v.recorded_at DESC) FROM public.vital_signs v WHERE v.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END,
    'encounters', CASE WHEN is_clinical THEN COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC) FROM public.encounters e WHERE e.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END,
    'labs', CASE WHEN is_clinical THEN COALESCE((SELECT jsonb_agg(to_jsonb(l) ORDER BY l.created_at DESC) FROM public.lab_orders l WHERE l.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END,
    'prescriptions', CASE WHEN is_clinical THEN COALESCE((SELECT jsonb_agg(to_jsonb(rx) ORDER BY rx.created_at DESC) FROM public.prescriptions rx WHERE rx.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END,
    'invoices', CASE WHEN is_billing OR is_front_desk THEN COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.created_at DESC) FROM public.invoices i WHERE i.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END,
    'documents', CASE WHEN is_clinical OR is_front_desk THEN COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.created_at DESC) FROM public.patient_documents d WHERE d.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END,
    'admissions', CASE WHEN is_clinical THEN COALESCE((SELECT jsonb_agg(to_jsonb(ad) ORDER BY ad.admitted_at DESC) FROM public.admissions ad WHERE ad.patient_id = _patient_id), '[]'::jsonb) ELSE '[]'::jsonb END
  ) INTO result FROM public.patients p WHERE p.id = _patient_id;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_patient_hub_snapshot(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_patient_hub_snapshot(UUID) TO authenticated;
