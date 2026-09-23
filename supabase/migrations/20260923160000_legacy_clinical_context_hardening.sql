-- Harden remaining legacy clinical read/specialty boundaries without changing their public API signatures.

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
      WHEN is_clinical THEN jsonb_build_object(
        'id',p.id,'patient_code',p.patient_code,'first_name',p.first_name,'last_name',p.last_name,
        'date_of_birth',p.date_of_birth,'gender',p.gender,'email',p.email,'phone',p.phone,
        'address',p.address,'city',p.city,'ghana_card_number',p.ghana_card_number,
        'blood_group',p.blood_group,'genotype',p.genotype,'allergies',p.allergies,
        'chronic_conditions',p.chronic_conditions,'insurance_provider',p.insurance_provider,
        'insurance_number',p.insurance_number,'insurance_group_number',p.insurance_group_number,
        'insurance_expiry',p.insurance_expiry,'emergency_contact_name',p.emergency_contact_name,
        'emergency_contact_phone',p.emergency_contact_phone,'emergency_contact_relation',p.emergency_contact_relation,
        'status',p.status
      )
      ELSE jsonb_build_object(
        'id',p.id,'patient_code',p.patient_code,'first_name',p.first_name,'last_name',p.last_name,
        'date_of_birth',p.date_of_birth,'gender',p.gender,'phone',p.phone,'email',p.email,
        'address',p.address,'status',p.status
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
  ) INTO result
  FROM public.patients p
  WHERE p.id = _patient_id;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_ophthalmology_exam(
  _patient_id UUID,
  _visual_acuity TEXT,
  _refraction TEXT,
  _keratometry TEXT,
  _intraocular_pressure NUMERIC,
  _color_vision TEXT,
  _fundus_notes TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'ophthalmologist')) THEN
    RAISE EXCEPTION 'Ophthalmology clinical role required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive') THEN
    RAISE EXCEPTION 'Patient not found or inactive';
  END IF;
  IF _intraocular_pressure IS NOT NULL AND _intraocular_pressure < 0 THEN RAISE EXCEPTION 'Intraocular pressure cannot be negative'; END IF;

  INSERT INTO public.ophthalmology_exams(patient_id, visual_acuity, refraction, keratometry, intraocular_pressure, color_vision, fundus_notes, performed_by)
  VALUES (_patient_id, NULLIF(trim(_visual_acuity),''), NULLIF(trim(_refraction),''), NULLIF(trim(_keratometry),''), _intraocular_pressure, NULLIF(trim(_color_vision),''), NULLIF(trim(_fundus_notes),''), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_walk_in_billable_service(
  _patient_id UUID,
  _service_code TEXT,
  _quantity NUMERIC DEFAULT 1,
  _notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE t public.service_tariffs%ROWTYPE; so UUID; uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')) THEN RAISE EXCEPTION 'Billing access denied'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active') <> 'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
  IF _quantity IS NULL OR _quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
  IF NULLIF(btrim(_service_code),'') IS NULL THEN RAISE EXCEPTION 'Service code is required'; END IF;
  SELECT * INTO t FROM public.service_tariffs WHERE service_code=btrim(_service_code) AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active service tariff not found'; END IF;
  INSERT INTO public.service_orders(patient_id,department,service_name,amount,quantity,unit_price,status,requested_by,created_by,order_type,service_code,payment_required,notes)
  VALUES(_patient_id,t.department,t.service_name,t.amount*_quantity,_quantity,t.amount,'pending_payment_approval',uid,uid,'walk_in',t.service_code,true,NULLIF(btrim(_notes),''))
  RETURNING id INTO so;
  RETURN jsonb_build_object('service_order_id',so,'amount',t.amount*_quantity,'status','pending_payment_approval');
END;
$$;

REVOKE ALL ON FUNCTION public.get_patient_hub_snapshot(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_ophthalmology_exam(UUID,TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_walk_in_billable_service(UUID,TEXT,NUMERIC,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_hub_snapshot(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_ophthalmology_exam(UUID,TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_walk_in_billable_service(UUID,TEXT,NUMERIC,TEXT) TO authenticated;
