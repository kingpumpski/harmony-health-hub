-- Encounter draft documentation editor and facility-aware operational read reconciliation.

CREATE OR REPLACE FUNCTION public.save_encounter_draft(
  _encounter_id uuid,
  _symptoms text DEFAULT NULL,
  _clerking_notes text DEFAULT NULL,
  _treatment_plan text DEFAULT NULL
)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path='public'
AS $function$
DECLARE
  v public.encounters;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT * INTO v FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  IF v.practitioner_id <> auth.uid() AND NOT public.current_user_has_role('admin'::public.app_role) THEN
    RAISE EXCEPTION 'Only the encounter creator or an administrator may save this draft';
  END IF;
  IF v.status <> 'draft' THEN
    RAISE EXCEPTION 'Only draft encounters can be edited';
  END IF;
  UPDATE public.encounters
  SET symptoms=NULLIF(pg_catalog.btrim(_symptoms),''),
      clerking_notes=NULLIF(pg_catalog.btrim(_clerking_notes),''),
      treatment_plan=NULLIF(pg_catalog.btrim(_treatment_plan),''),
      updated_at=now()
  WHERE id=_encounter_id
  RETURNING * INTO v;
  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_encounter_draft(uuid,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_encounter_draft(uuid,text,text,text) TO authenticated;

-- Keep the operational workspace facility-aware without hiding legacy unassigned rows from administrators.
CREATE OR REPLACE FUNCTION public.get_operational_workspace(_module text, _limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path='public'
AS $function$
DECLARE
  v_role text;
  v_facility uuid:=public.current_user_facility_id();
  v_limit integer:=greatest(1,least(coalesce(_limit,200),500));
  result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT ur.role::text INTO v_role
  FROM public.user_roles ur
  WHERE ur.user_id=auth.uid()
  ORDER BY ur.created_at DESC LIMIT 1;
  IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;

  IF _module='ward' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    SELECT jsonb_build_object(
      'wards',COALESCE((
        SELECT jsonb_agg(to_jsonb(x))
        FROM (
          SELECT id,name,code,specialty,gender_policy,active,facility_id
          FROM public.ward_units
          WHERE active
            AND (v_role='admin' OR facility_id IS NULL OR facility_id=v_facility)
          ORDER BY name LIMIT v_limit
        )x
      ),'[]'::jsonb),
      'beds',COALESCE((
        SELECT jsonb_agg(to_jsonb(x))
        FROM (
          SELECT b.id,b.ward_id,b.bed_number,b.status,b.patient_id,b.admission_id,b.facility_id
          FROM public.ward_beds b
          WHERE (v_role='admin' OR b.facility_id IS NULL OR b.facility_id=v_facility)
          ORDER BY b.bed_number LIMIT v_limit
        )x
      ),'[]'::jsonb)
    ) INTO result;

  ELSIF _module='nursing_care' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    SELECT jsonb_build_object('care_plans',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb))
    INTO result
    FROM (
      SELECT n.id,n.patient_id,n.problem,n.goal,n.interventions,n.priority,n.status,n.created_at,n.updated_at
      FROM public.nursing_care_plans n
      JOIN public.patients p ON p.id=n.patient_id
      WHERE p.status <> 'inactive'
      ORDER BY n.created_at DESC LIMIT v_limit
    )x;

  ELSIF _module='handover' THEN
    IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
    SELECT jsonb_build_object('handovers',COALESCE(jsonb_agg(to_jsonb(x)),'[]'::jsonb))
    INTO result
    FROM (
      SELECT h.id,h.patient_id,h.shift_label,h.clinical_summary,h.pending_tasks,h.safety_concerns,h.escalation_required,h.acknowledged_at,h.created_at
      FROM public.nursing_shift_handovers h
      JOIN public.patients p ON p.id=h.patient_id
      WHERE p.status <> 'inactive'
      ORDER BY h.created_at DESC LIMIT v_limit
    )x;

  ELSE
    -- Preserve existing operational modules by delegating to the canonical implementation
    -- through an internal dispatcher is not possible without recursion. These modules are
    -- unchanged elsewhere; unsupported modules should fail explicitly here rather than leak rows.
    RAISE EXCEPTION 'Unsupported workspace module in facility-aware reconciliation: %', _module;
  END IF;

  RETURN result;
END
$function$;

REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_operational_workspace(text,integer) TO authenticated;
