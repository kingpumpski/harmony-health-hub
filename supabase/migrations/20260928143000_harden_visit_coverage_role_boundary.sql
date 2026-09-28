-- Narrow visit-coverage activation to the roles that already own
-- registration/accounts/clinical coverage workflows. Do not inherit the
-- broader legacy is_clinical_staff set (which includes canteen).

CREATE OR REPLACE FUNCTION public.activate_patient_visit_coverage(
  _patient_id uuid,
  _source text,
  _appointment_id uuid DEFAULT NULL,
  _authorization_date date DEFAULT CURRENT_DATE
)
RETURNS public.patient_visit_authorizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  coverage RECORD;
  result public.patient_visit_authorizations;
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _source NOT IN ('appointment','accounts') THEN
    RAISE EXCEPTION 'Invalid activation source';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'accountant')
    OR public.has_role(uid,'front_desk')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'lab_technician')
    OR public.has_role(uid,'radiologist')
    OR public.has_role(uid,'radiology_technician')
    OR public.has_role(uid,'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Only authorised staff can activate visit coverage';
  END IF;

  SELECT * INTO coverage
  FROM public.patient_coverage_details(_patient_id);

  IF coverage.coverage_type IS NULL THEN
    RAISE EXCEPTION 'Patient has no active insurance or partnered-company coverage';
  END IF;

  IF _appointment_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.appointments
       WHERE id = _appointment_id
         AND patient_id = _patient_id
     )
  THEN
    RAISE EXCEPTION 'Appointment does not belong to this patient';
  END IF;

  INSERT INTO public.patient_visit_authorizations(
    patient_id,
    authorization_date,
    coverage_type,
    payer_name,
    activated_by,
    activation_source,
    appointment_id,
    active
  )
  VALUES(
    _patient_id,
    _authorization_date,
    coverage.coverage_type,
    coverage.payer_name,
    uid,
    _source,
    _appointment_id,
    true
  )
  ON CONFLICT(patient_id,authorization_date) DO UPDATE
  SET coverage_type=EXCLUDED.coverage_type,
      payer_name=EXCLUDED.payer_name,
      activated_by=EXCLUDED.activated_by,
      activation_source=EXCLUDED.activation_source,
      appointment_id=COALESCE(
        EXCLUDED.appointment_id,
        patient_visit_authorizations.appointment_id
      ),
      active=true
  RETURNING * INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date)
  TO authenticated;
