-- Harden service-order writes against unresolved or cross-facility patient/encounter lineage.
-- This trigger runs before service_orders insert/update and complements RPC role checks.
CREATE OR REPLACE FUNCTION public.validate_service_order_encounter()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_patient_facility uuid;
  v_encounter public.encounters;
  v_active_facility uuid := public.current_user_facility_id();
  v_is_privileged boolean := public.current_user_has_role('admin') OR public.current_user_has_role('it_admin');
BEGIN
  IF NEW.patient_id IS NULL THEN
    RAISE EXCEPTION 'A patient is required for a service order';
  END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p WHERE p.id = NEW.patient_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved; reconcile the patient before creating a service order';
  END IF;

  IF NEW.facility_id IS NOT NULL AND NEW.facility_id <> v_patient_facility THEN
    RAISE EXCEPTION 'Service order facility does not match patient facility';
  END IF;

  IF NOT v_is_privileged AND (v_active_facility IS NULL OR v_active_facility <> v_patient_facility) THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context';
  END IF;

  IF NEW.encounter_id IS NOT NULL THEN
    SELECT e.* INTO v_encounter
    FROM public.encounters e WHERE e.id = NEW.encounter_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
    IF v_encounter.patient_id <> NEW.patient_id THEN
      RAISE EXCEPTION 'Service order patient does not match encounter patient';
    END IF;
    IF v_encounter.facility_id IS NULL THEN
      RAISE EXCEPTION 'Encounter facility attribution is unresolved; reconcile the encounter before creating a service order';
    END IF;
    IF v_encounter.facility_id <> v_patient_facility
       OR (NEW.facility_id IS NOT NULL AND NEW.facility_id <> v_encounter.facility_id) THEN
      RAISE EXCEPTION 'Service order, encounter, and patient facility lineage must match';
    END IF;
    IF v_encounter.status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot create a service order for a completed or cancelled encounter';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_service_order_encounter() FROM PUBLIC, anon, authenticated;

DO $contract$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'service_order_encounter_guard'
      AND tgrelid = 'public.service_orders'::regclass
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Expected service_order_encounter_guard trigger is missing';
  END IF;
END;
$contract$;
