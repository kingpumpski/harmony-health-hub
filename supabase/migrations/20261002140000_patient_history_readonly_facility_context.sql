BEGIN;

-- STABLE read RPCs execute in a read-only transaction. The write-oriented
-- assert_patient_facility_context helper takes a row lock (FOR SHARE), which
-- raises SQLSTATE 25006 when called from those read RPCs. Keep the same
-- authorization/facility checks but provide a non-locking helper for reads.

CREATE OR REPLACE FUNCTION public.assert_patient_facility_read_context(_patient_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  patient_facility uuid;
  active_facility uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;

  SELECT p.facility_id
  INTO patient_facility
  FROM public.patients p
  WHERE p.id = _patient_id
    AND coalesce(p.status,'active') <> 'inactive';

  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
  IF patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;

  IF public.has_role(uid,'admin'::public.app_role)
     OR public.has_role(uid,'it_admin'::public.app_role) THEN
    RETURN patient_facility;
  END IF;

  IF active_facility IS NULL THEN RAISE EXCEPTION 'Active facility context is required'; END IF;
  IF patient_facility IS DISTINCT FROM active_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context';
  END IF;

  RETURN patient_facility;
END;
$function$;

REVOKE ALL ON FUNCTION public.assert_patient_facility_read_context(uuid) FROM PUBLIC, anon, authenticated;

-- Rebuild only the read-only functions that currently invoke the locking
-- write helper. All other authorization predicates and result projections
-- are preserved verbatim from the installed function definitions.
DO $migration$
DECLARE
  v_signature regprocedure;
  v_definition text;
  v_signatures regprocedure[] := ARRAY[
    'public.get_attending_patient_history(uuid,uuid)'::regprocedure,
    'public.get_patient_admission_history(uuid)'::regprocedure,
    'public.get_patient_appointments(uuid,integer)'::regprocedure,
    'public.get_patient_bmi_context(uuid)'::regprocedure,
    'public.get_patient_current_treatment_snapshot(uuid,uuid)'::regprocedure,
    'public.get_patient_hub_clinical_snapshot(uuid)'::regprocedure
  ];
BEGIN
  FOREACH v_signature IN ARRAY v_signatures LOOP
    v_definition := pg_catalog.pg_get_functiondef(v_signature);
    IF pg_catalog.strpos(v_definition, 'PERFORM public.assert_patient_facility_context(_patient_id);') = 0 THEN
      RAISE EXCEPTION 'Expected facility assertion missing from %; refusing partial read-RPC repair', v_signature;
    END IF;
    v_definition := pg_catalog.replace(
      v_definition,
      'PERFORM public.assert_patient_facility_context(_patient_id);',
      'PERFORM public.assert_patient_facility_read_context(_patient_id);'
    );
    EXECUTE v_definition;
  END LOOP;
END;
$migration$;

NOTIFY pgrst, 'reload schema';
COMMIT;
