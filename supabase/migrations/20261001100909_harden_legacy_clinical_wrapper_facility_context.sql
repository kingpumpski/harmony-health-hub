BEGIN;

CREATE OR REPLACE FUNCTION public.get_pending_specialist_referrals()
RETURNS TABLE(
  referral_id uuid,
  patient_id uuid,
  patient_name text,
  telephone text,
  specialty text,
  appointment_date timestamptz,
  referred_at timestamptz,
  status text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Specialist referral access denied';
  END IF;
  IF public.has_role(uid,'admin'::public.app_role)
     OR public.has_role(uid,'it_admin'::public.app_role) THEN
    RETURN QUERY
      SELECT r.id,r.patient_id,concat(p.first_name,' ',p.last_name),p.phone,
             r.specialty,r.appointment_date,r.created_at,r.status
      FROM public.patient_referrals r
      JOIN public.patients p ON p.id=r.patient_id
      WHERE r.status IN ('requested','accepted','scheduled')
        AND r.specialty IS NOT NULL
        AND p.facility_id IS NOT NULL
      ORDER BY r.appointment_date NULLS LAST,r.created_at ASC;
    RETURN;
  END IF;
  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Active facility context is required';
  END IF;
  RETURN QUERY
    SELECT r.id,r.patient_id,concat(p.first_name,' ',p.last_name),p.phone,
           r.specialty,r.appointment_date,r.created_at,r.status
    FROM public.patient_referrals r
    JOIN public.patients p ON p.id=r.patient_id
    WHERE r.status IN ('requested','accepted','scheduled')
      AND r.specialty IS NOT NULL
      AND p.facility_id IS NOT NULL
      AND p.facility_id=v_facility
    ORDER BY r.appointment_date NULLS LAST,r.created_at ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.patient_coverage_details(_patient_id uuid)
RETURNS TABLE(coverage_type text,payer_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'accountant'::public.app_role)
    OR public.has_role(uid,'front_desk'::public.app_role)
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
    OR public.has_role(uid,'lab_technician'::public.app_role)
    OR public.has_role(uid,'radiologist'::public.app_role)
    OR public.has_role(uid,'radiology_technician'::public.app_role)
    OR public.has_role(uid,'pharmacist'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Patient coverage access denied';
  END IF;
  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id=_patient_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient does not exist';
  END IF;
  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved';
  END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
  ) THEN
    IF v_facility IS NULL THEN
      RAISE EXCEPTION 'Active facility context is required';
    END IF;
    IF v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Patient belongs to a different facility context';
    END IF;
  END IF;
  RETURN QUERY
    SELECT CASE
             WHEN NULLIF(pg_catalog.btrim(p.insurance_provider),'') IS NOT NULL THEN 'insurance'
             WHEN NULLIF(pg_catalog.btrim(p.partner_company),'') IS NOT NULL THEN 'partner_company'
           END,
           COALESCE(NULLIF(pg_catalog.btrim(p.insurance_provider),''),
                    NULLIF(pg_catalog.btrim(p.partner_company),''))
    FROM public.patients p
    WHERE p.id=_patient_id
      AND (NULLIF(pg_catalog.btrim(p.insurance_provider),'') IS NOT NULL
           OR NULLIF(pg_catalog.btrim(p.partner_company),'') IS NOT NULL)
      AND (p.insurance_expiry IS NULL OR p.insurance_expiry>=CURRENT_DATE);
END;
$function$;

REVOKE ALL ON FUNCTION public.get_pending_specialist_referrals() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pending_specialist_referrals() TO authenticated;
REVOKE ALL ON FUNCTION public.patient_coverage_details(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.patient_coverage_details(uuid) TO authenticated;

COMMIT;
