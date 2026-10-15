BEGIN;

CREATE OR REPLACE FUNCTION public.set_patient_insurance_company(
  _patient_id uuid,
  _insurance_company_id uuid
)
RETURNS public.patients
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_patient public.patients;
  v_company_name text;
  v_old_company uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'front_desk'::public.app_role)
    OR public.has_role(uid,'accountant'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Patient insurance administration access required';
  END IF;

  IF _patient_id IS NULL THEN
    RAISE EXCEPTION 'Patient is required';
  END IF;

  SELECT * INTO v_patient
  FROM public.patients
  WHERE id=_patient_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  v_old_company := v_patient.insurance_company_id;

  IF _insurance_company_id IS NOT NULL THEN
    SELECT c.name INTO v_company_name
    FROM public.insurance_companies c
    WHERE c.id=_insurance_company_id
      AND c.active=true;

    IF v_company_name IS NULL THEN
      RAISE EXCEPTION 'Active canonical insurance company not found';
    END IF;
  END IF;

  UPDATE public.patients
  SET insurance_company_id=_insurance_company_id,
      insurance_provider=CASE
        WHEN v_company_name IS NOT NULL THEN v_company_name
        ELSE insurance_provider
      END,
      updated_at=now()
  WHERE id=_patient_id
  RETURNING * INTO v_patient;

  PERFORM public.record_system_audit(
    'patient_insurance_company_linked',
    'insurance',
    'patient',
    v_patient.id,
    'info',
    jsonb_build_object(
      'previous_insurance_company_id', v_old_company,
      'insurance_company_id', _insurance_company_id,
      'actor_id', uid
    )
  );

  RETURN v_patient;
END;
$function$;

REVOKE ALL ON FUNCTION public.set_patient_insurance_company(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_patient_insurance_company(uuid,uuid) TO authenticated;

COMMIT;