-- Reconcile SECURITY DEFINER RPCs that depended on the intentionally revoked
-- is_clinical_staff(UUID) helper. These functions remain client-facing, so they
-- use explicit role unions and keep their authenticated execution boundary.

CREATE OR REPLACE FUNCTION public.create_patient_appointment(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT DEFAULT NULL,
  _reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_appt public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'front_desk'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Appointment creation denied';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.patients
    WHERE id=_patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN
    RAISE EXCEPTION 'Active patient not found';
  END IF;
  IF _scheduled_at IS NULL THEN
    RAISE EXCEPTION 'Appointment time is required';
  END IF;

  v_appt:=public.create_appointment_workflow(_patient_id,_scheduled_at,_department,_reason);
  RETURN jsonb_build_object('appointment_id',v_appt.id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;


CREATE OR REPLACE FUNCTION public.get_pending_specialist_referrals()
RETURNS TABLE(
  referral_id UUID,
  patient_id UUID,
  patient_name TEXT,
  telephone TEXT,
  specialty TEXT,
  appointment_date TIMESTAMPTZ,
  referred_at TIMESTAMPTZ,
  status TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Specialist referral access denied';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.patient_id,
    concat(p.first_name,' ',p.last_name),
    p.phone,
    r.specialty,
    r.appointment_date,
    r.created_at,
    r.status
  FROM public.patient_referrals r
  JOIN public.patients p ON p.id=r.patient_id
  WHERE r.status IN ('requested','accepted','scheduled')
    AND r.specialty IS NOT NULL
    AND COALESCE(p.status,'active') <> 'inactive'
  ORDER BY r.appointment_date NULLS LAST,r.created_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_pending_specialist_referrals() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pending_specialist_referrals() TO authenticated;


CREATE OR REPLACE FUNCTION public.patient_coverage_details(_patient_id UUID)
RETURNS TABLE(coverage_type TEXT,payer_name TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'accountant'::public.app_role)
    OR public.has_role(auth.uid(),'front_desk'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Patient coverage access denied';
  END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN NULLIF(trim(p.insurance_provider),'') IS NOT NULL THEN 'insurance'
      WHEN NULLIF(trim(p.partner_company),'') IS NOT NULL THEN 'partner_company'
    END,
    COALESCE(NULLIF(trim(p.insurance_provider),''),NULLIF(trim(p.partner_company),''))
  FROM public.patients p
  WHERE p.id=_patient_id
    AND COALESCE(p.status,'active') <> 'inactive'
    AND (
      NULLIF(trim(p.insurance_provider),'') IS NOT NULL
      OR NULLIF(trim(p.partner_company),'') IS NOT NULL
    )
    AND (p.insurance_expiry IS NULL OR p.insurance_expiry>=CURRENT_DATE);
END;
$$;

REVOKE ALL ON FUNCTION public.patient_coverage_details(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.patient_coverage_details(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.attach_lab_catalogue_to_order(
  _lab_order_id UUID,
  _catalogue_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_catalog public.lab_test_catalogue%ROWTYPE;
  v_patient_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(),'lab_technician'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Clinical staff access required';
  END IF;

  SELECT patient_id
    INTO v_patient_id
  FROM public.lab_orders
  WHERE id=_lab_order_id
  FOR UPDATE;

  IF v_patient_id IS NULL THEN
    RAISE EXCEPTION 'Laboratory order not found';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.patients
    WHERE id=v_patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN
    RAISE EXCEPTION 'Laboratory order patient is inactive or missing';
  END IF;

  SELECT *
    INTO v_catalog
  FROM public.lab_test_catalogue
  WHERE id=_catalogue_id AND active=true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active laboratory catalogue item not found';
  END IF;

  UPDATE public.lab_orders
  SET lab_test_catalogue_id=_catalogue_id,
      test_name=v_catalog.test_name,
      test_category=v_catalog.category
  WHERE id=_lab_order_id;

  RETURN jsonb_build_object(
    'lab_order_id',_lab_order_id,
    'catalogue_id',_catalogue_id,
    'test_name',v_catalog.test_name
  );
END;
$$;

REVOKE ALL ON FUNCTION public.attach_lab_catalogue_to_order(UUID,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.attach_lab_catalogue_to_order(UUID,UUID) TO authenticated;
