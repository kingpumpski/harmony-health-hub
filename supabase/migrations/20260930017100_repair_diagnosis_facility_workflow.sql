-- Repair diagnosis authoring for legacy encounters that are being actively worked.
-- Direct diagnosis DML remains revoked; only authenticated clinical workflow RPCs can reach this trigger.
CREATE OR REPLACE FUNCTION public.sync_child_facility_from_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_facility uuid;
  v_reconciliation boolean := coalesce(current_setting('hms.facility_reconciliation', true), 'off') = 'on';
BEGIN
  IF tg_table_name='department_queues' THEN
    SELECT so.facility_id INTO v_facility FROM public.service_orders so WHERE so.id=new.service_order_id;
  ELSIF tg_table_name='lab_orders' THEN
    SELECT e.facility_id INTO v_facility FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id; END IF;
  ELSIF tg_table_name='lab_results' THEN
    SELECT lo.facility_id INTO v_facility FROM public.lab_orders lo WHERE lo.id=new.lab_order_id;
  ELSIF tg_table_name='imaging_orders' THEN
    SELECT e.facility_id INTO v_facility FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id; END IF;
  ELSIF tg_table_name='prescriptions' THEN
    SELECT e.facility_id INTO v_facility FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id; END IF;
  ELSIF tg_table_name='diagnoses' THEN
    SELECT e.facility_id INTO v_facility FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
    IF v_facility IS NULL AND auth.uid() IS NOT NULL THEN
      v_facility := public.current_user_facility_id();
      IF v_facility IS NOT NULL AND new.encounter_id IS NOT NULL THEN
        UPDATE public.encounters SET facility_id=v_facility, updated_at=now()
        WHERE id=new.encounter_id AND facility_id IS NULL;
      END IF;
      IF v_facility IS NOT NULL AND new.patient_id IS NOT NULL THEN
        UPDATE public.patients SET facility_id=v_facility, updated_at=now()
        WHERE id=new.patient_id AND facility_id IS NULL;
      END IF;
    END IF;
  END IF;

  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Parent clinical record has no facility attribution';
  END IF;

  IF new.facility_id IS NULL THEN
    IF tg_op='UPDATE' THEN RAISE EXCEPTION 'Facility attribution cannot be cleared'; END IF;
    new.facility_id := v_facility;
  ELSIF new.facility_id<>v_facility
    AND NOT (v_reconciliation AND (public.current_user_has_role('admin') OR public.current_user_has_role('it_admin'))) THEN
    RAISE EXCEPTION 'Facility lineage mismatch';
  END IF;
  RETURN new;
END
$function$;

REVOKE EXECUTE ON FUNCTION public.sync_child_facility_from_parent() FROM PUBLIC, anon, authenticated;
