-- Gate A: harden encounter creation and prevent cross-facility inheritance from unresolved admission lineage.
DO $migration$
DECLARE
  v_definition text;
  v_anchor text;
BEGIN
  v_definition := pg_catalog.pg_get_functiondef('public.create_encounter_workflow(uuid,text,text)'::regprocedure);
  v_anchor := 'IF NOT FOUND THEN RAISE EXCEPTION ''Patient does not exist''; END IF;';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected patient lookup anchor not found for create_encounter_workflow';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,v_anchor || E'\n  PERFORM public.assert_patient_facility_context(_patient_id);');

  v_anchor := 'AND (a.facility_id IS NULL OR a.facility_id=v_facility)';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected admission facility filter not found';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,'AND a.facility_id=v_facility');

  v_anchor := 'AND (e.facility_id IS NULL OR e.facility_id=v_facility)';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected source encounter facility filter not found';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,'AND e.facility_id=v_facility');

  v_anchor := 'INSERT INTO public.diagnoses(encounter_id,diagnosis,is_principal,icd_code,ai_suggested)';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected inherited diagnosis insert not found';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,'INSERT INTO public.diagnoses(encounter_id,diagnosis,is_principal,icd_code,ai_suggested,facility_id)');

  v_anchor := 'SELECT result.id,d.diagnosis,d.is_principal,d.icd_code,d.ai_suggested';
  IF pg_catalog.strpos(v_definition,v_anchor)=0 THEN
    RAISE EXCEPTION 'Expected inherited diagnosis projection not found';
  END IF;
  v_definition := pg_catalog.replace(v_definition,v_anchor,'SELECT result.id,d.diagnosis,d.is_principal,d.icd_code,d.ai_suggested,v_facility');

  EXECUTE v_definition;
END;
$migration$;

ALTER FUNCTION public.create_encounter_workflow(uuid,text,text) SET search_path='';
REVOKE ALL ON FUNCTION public.create_encounter_workflow(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_workflow(uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';