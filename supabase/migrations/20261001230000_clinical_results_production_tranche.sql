-- Clinical results production tranche: encounter-scoped diagnoses, acknowledgement audit, and
-- role-separated read contracts for laboratory and radiology results.

-- Repair the diagnosis facility trigger created by the already-applied lineage migration.
-- The clean-install diagnoses table carries patient identity through encounter_id.
CREATE OR REPLACE FUNCTION public.sync_child_facility_from_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_facility uuid;
  v_reconciliation boolean := coalesce(pg_catalog.current_setting('hms.facility_reconciliation', true), 'off') = 'on';
BEGIN
  IF tg_table_name='department_queues' THEN
    SELECT so.facility_id INTO v_facility
    FROM public.service_orders so WHERE so.id=new.service_order_id;
  ELSIF tg_table_name='lab_orders' THEN
    SELECT e.facility_id INTO v_facility
    FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
  ELSIF tg_table_name='lab_results' THEN
    SELECT lo.facility_id INTO v_facility
    FROM public.lab_orders lo WHERE lo.id=new.lab_order_id;
  ELSIF tg_table_name='imaging_orders' THEN
    SELECT e.facility_id INTO v_facility
    FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
  ELSIF tg_table_name='prescriptions' THEN
    SELECT e.facility_id INTO v_facility
    FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
  ELSIF tg_table_name='diagnoses' THEN
    SELECT COALESCE(e.facility_id,p.facility_id) INTO v_facility
    FROM public.encounters e
    JOIN public.patients p ON p.id=e.patient_id
    WHERE e.id=new.encounter_id;
  END IF;

  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Parent clinical record has no facility attribution; reconcile the parent record first';
  END IF;

  IF new.facility_id IS NULL THEN
    IF tg_op='UPDATE' THEN
      RAISE EXCEPTION 'Facility attribution cannot be cleared';
    END IF;
    new.facility_id := v_facility;
  ELSIF new.facility_id<>v_facility
    AND NOT (
      v_reconciliation
      AND (public.current_user_has_role('admin') OR public.current_user_has_role('it_admin'))
    ) THEN
    RAISE EXCEPTION 'Facility lineage mismatch';
  END IF;

  RETURN new;
END;
$function$;

ALTER TABLE public.imaging_orders
  ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz,
  ADD COLUMN IF NOT EXISTS acknowledged_by uuid REFERENCES auth.users(id);

ALTER TABLE public.lab_results
  ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz,
  ADD COLUMN IF NOT EXISTS acknowledged_by uuid REFERENCES auth.users(id);

CREATE OR REPLACE FUNCTION public.get_clinician_imaging_results(_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE uid uuid := auth.uid(); result jsonb;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
   OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN
   RAISE EXCEPTION 'Clinical report access is not permitted';
 END IF;
 _limit := LEAST(GREATEST(COALESCE(_limit,100),1),300);
 SELECT COALESCE(jsonb_agg(row_data ORDER BY updated_at DESC),'[]'::jsonb) INTO result
 FROM (
   SELECT io.updated_at, jsonb_build_object(
    'id',io.id,'patient_id',io.patient_id,'study_name',io.study_name,'modality',io.modality,
    'priority',COALESCE(io.priority,'routine'),'report',io.report,'impression',io.impression,
    'encounter_id',io.encounter_id,'created_at',io.created_at,'updated_at',io.updated_at,
    'completed_at',io.completed_at,'acknowledged_at',io.acknowledged_at,'acknowledged_by',io.acknowledged_by,
    'clinical_indication',io.clinical_indication,
    'prescriber_id',io.requested_by,
    'prescriber_name',NULLIF(trim(coalesce(req.first_name,'')||' '||coalesce(req.last_name,'')),''),
    'diagnoses',COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',d.id,'diagnosis',d.diagnosis,'icd_code',d.icd_code,'is_principal',d.is_principal)
      ORDER BY d.is_principal DESC,d.created_at ASC) FROM public.diagnoses d
      JOIN public.encounters diagnosis_encounter ON diagnosis_encounter.id=d.encounter_id
        AND diagnosis_encounter.patient_id=io.patient_id
      WHERE d.encounter_id=io.encounter_id
    ),'[]'::jsonb),
    'patients',jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code)
   ) row_data
   FROM public.imaging_orders io
   JOIN public.patients p ON p.id=io.patient_id
   LEFT JOIN public.encounters e ON e.id=io.encounter_id
   LEFT JOIN public.profiles req ON req.id=io.requested_by
   WHERE io.status='completed'
     AND (NULLIF(trim(coalesce(io.report,'')),'') IS NOT NULL OR NULLIF(trim(coalesce(io.impression,'')),'') IS NOT NULL)
     AND ((COALESCE(io.facility_id,e.facility_id,p.facility_id) IS NOT NULL
       AND public.current_user_has_facility_access(COALESCE(io.facility_id,e.facility_id,p.facility_id)))
       OR (COALESCE(io.facility_id,e.facility_id,p.facility_id) IS NULL AND (io.requested_by=uid OR e.practitioner_id=uid)))
   ORDER BY io.updated_at DESC LIMIT _limit
 ) q;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.get_clinician_lab_results(_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE uid uuid := auth.uid(); result jsonb;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
   OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN
   RAISE EXCEPTION 'Clinical report access is not permitted';
 END IF;
 _limit := LEAST(GREATEST(COALESCE(_limit,100),1),300);
 SELECT COALESCE(jsonb_agg(row_data ORDER BY approved_at DESC NULLS LAST),'[]'::jsonb) INTO result
 FROM (
   SELECT r.approved_at, jsonb_build_object(
    'id',r.id,'lab_order_id',o.id,'patient_id',o.patient_id,'encounter_id',o.encounter_id,
    'test_name',o.test_name,'test_category',o.test_category,'priority',COALESCE(o.priority,'routine'),
    'clinical_notes',o.clinical_notes,'result_data',r.result_data,'parameter_results',r.parameter_results,
    'result_text',r.result_data->>'value','interpretation',r.interpretation,'is_abnormal',COALESCE(r.is_abnormal,false),
    'status',r.status,'entered_at',r.entered_at,'approved_at',r.approved_at,'acknowledged_at',r.acknowledged_at,
    'acknowledged_by',r.acknowledged_by,'numeric_value',r.numeric_value,'unit',r.unit,
    'reference_low',r.reference_low,'reference_high',r.reference_high,'abnormal_flag',r.abnormal_flag,
    'prescriber_id',o.ordered_by,
    'prescriber_name',NULLIF(trim(coalesce(req.first_name,'')||' '||coalesce(req.last_name,'')),''),
    'diagnoses',COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',d.id,'diagnosis',d.diagnosis,'icd_code',d.icd_code,'is_principal',d.is_principal)
      ORDER BY d.is_principal DESC,d.created_at ASC) FROM public.diagnoses d
      JOIN public.encounters diagnosis_encounter ON diagnosis_encounter.id=d.encounter_id
        AND diagnosis_encounter.patient_id=o.patient_id
      WHERE d.encounter_id=o.encounter_id
    ),'[]'::jsonb),
    'patients',jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code)
   ) row_data
   FROM public.lab_results r JOIN public.lab_orders o ON o.id=r.lab_order_id
   JOIN public.patients p ON p.id=o.patient_id LEFT JOIN public.encounters e ON e.id=o.encounter_id
   LEFT JOIN public.profiles req ON req.id=o.ordered_by
   WHERE r.status='approved' AND o.status='approved'
     AND ((COALESCE(o.facility_id,e.facility_id,p.facility_id) IS NOT NULL
       AND public.current_user_has_facility_access(COALESCE(o.facility_id,e.facility_id,p.facility_id)))
       OR (COALESCE(o.facility_id,e.facility_id,p.facility_id) IS NULL AND (o.ordered_by=uid OR e.practitioner_id=uid)))
   ORDER BY r.approved_at DESC NULLS LAST LIMIT _limit
 ) q;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.acknowledge_imaging_result(_result_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE uid uuid:=auth.uid(); ok boolean;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
   OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorised'; END IF;
 UPDATE public.imaging_orders io SET acknowledged_at=COALESCE(io.acknowledged_at,now()), acknowledged_by=COALESCE(io.acknowledged_by,uid)
 WHERE io.id=_result_id AND io.status='completed'
   AND EXISTS (SELECT 1 FROM public.patients p LEFT JOIN public.encounters e ON e.id=io.encounter_id
     WHERE p.id=io.patient_id AND ((COALESCE(io.facility_id,e.facility_id,p.facility_id) IS NOT NULL
       AND public.current_user_has_facility_access(COALESCE(io.facility_id,e.facility_id,p.facility_id)))
       OR (COALESCE(io.facility_id,e.facility_id,p.facility_id) IS NULL AND (io.requested_by=uid OR e.practitioner_id=uid))));
 GET DIAGNOSTICS ok = ROW_COUNT;
 RETURN ok;
END $$;

CREATE OR REPLACE FUNCTION public.acknowledge_lab_result(_result_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE uid uuid:=auth.uid(); ok boolean;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
   OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Not authorised'; END IF;
 UPDATE public.lab_results r SET acknowledged_at=COALESCE(r.acknowledged_at,now()), acknowledged_by=COALESCE(r.acknowledged_by,uid)
 FROM public.lab_orders o
 WHERE r.id=_result_id AND r.lab_order_id=o.id AND r.status='approved' AND o.status='approved'
   AND EXISTS (SELECT 1 FROM public.patients p LEFT JOIN public.encounters e ON e.id=o.encounter_id
     WHERE p.id=o.patient_id AND ((COALESCE(o.facility_id,e.facility_id,p.facility_id) IS NOT NULL
       AND public.current_user_has_facility_access(COALESCE(o.facility_id,e.facility_id,p.facility_id)))
       OR (COALESCE(o.facility_id,e.facility_id,p.facility_id) IS NULL AND (o.ordered_by=uid OR e.practitioner_id=uid))));
 GET DIAGNOSTICS ok = ROW_COUNT;
 RETURN ok;
END $$;

REVOKE ALL ON FUNCTION public.get_clinician_imaging_results(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_clinician_imaging_results(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_clinician_lab_results(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_clinician_lab_results(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.acknowledge_imaging_result(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_imaging_result(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.acknowledge_lab_result(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_lab_result(uuid) TO authenticated;

ALTER PUBLICATION supabase_realtime ADD TABLE public.imaging_orders;

NOTIFY pgrst,'reload schema';
