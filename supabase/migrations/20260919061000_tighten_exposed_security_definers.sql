-- Tighten exposed SECURITY DEFINER wrappers identified by the production advisor.
-- Keep internal helper functions callable only from trusted database code and add
-- explicit application-role checks to client-facing wrappers.
REVOKE ALL ON FUNCTION public.is_clinical_staff(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.has_active_patient_visit_coverage(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_insurance_claim_lifecycle() FROM PUBLIC, anon, authenticated;

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
  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'front_desk'::public.app_role)
    OR public.is_clinical_staff((SELECT auth.uid()))
  ) THEN
    RAISE EXCEPTION 'Appointment creation denied';
  END IF;

  v_appt := public.create_appointment_workflow(_patient_id, _scheduled_at, _department, _reason);
  RETURN jsonb_build_object('appointment_id', v_appt.id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pending_specialist_referrals()
RETURNS TABLE(
  referral_id UUID, patient_id UUID, patient_name TEXT, telephone TEXT,
  specialty TEXT, appointment_date TIMESTAMPTZ, referred_at TIMESTAMPTZ, status TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.is_clinical_staff((SELECT auth.uid()))
  ) THEN
    RAISE EXCEPTION 'Specialist referral access denied';
  END IF;

  RETURN QUERY
  SELECT r.id, r.patient_id, concat(p.first_name,' ',p.last_name), p.phone,
         r.specialty, r.appointment_date, r.created_at, r.status
  FROM public.patient_referrals r
  JOIN public.patients p ON p.id=r.patient_id
  WHERE r.status IN ('requested','accepted','scheduled')
    AND r.specialty IS NOT NULL
  ORDER BY r.appointment_date NULLS LAST, r.created_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_pending_specialist_referrals() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pending_specialist_referrals() TO authenticated;

CREATE OR REPLACE FUNCTION public.patient_coverage_details(_patient_id UUID)
RETURNS TABLE(coverage_type TEXT, payer_name TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'accountant'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'front_desk'::public.app_role)
    OR public.is_clinical_staff((SELECT auth.uid()))
  ) THEN
    RAISE EXCEPTION 'Patient coverage access denied';
  END IF;

  RETURN QUERY
  SELECT CASE
           WHEN NULLIF(trim(p.insurance_provider),'') IS NOT NULL THEN 'insurance'
           WHEN NULLIF(trim(p.partner_company),'') IS NOT NULL THEN 'partner_company'
         END,
         COALESCE(NULLIF(trim(p.insurance_provider),''), NULLIF(trim(p.partner_company),''))
  FROM public.patients p
  WHERE p.id=_patient_id
    AND (NULLIF(trim(p.insurance_provider),'') IS NOT NULL OR NULLIF(trim(p.partner_company),'') IS NOT NULL)
    AND (p.insurance_expiry IS NULL OR p.insurance_expiry>=CURRENT_DATE);
END;
$$;

REVOKE ALL ON FUNCTION public.patient_coverage_details(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.patient_coverage_details(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.transition_insurance_claim(
  _claim_id UUID,
  _status TEXT DEFAULT NULL,
  _amount_approved NUMERIC DEFAULT NULL,
  _amount_paid NUMERIC DEFAULT NULL,
  _rejection_reason TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _to_status TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_status TEXT := COALESCE(NULLIF(_status,''), NULLIF(_to_status,''));
BEGIN
  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'accountant'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Insurance claim transition denied';
  END IF;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Claim status is required';
  END IF;

  RETURN public.transition_insurance_claim_canonical(
    _claim_id, v_status, _amount_approved, _amount_paid, _rejection_reason, _notes
  );
END;
$$;

REVOKE ALL ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT,TEXT) TO authenticated;
