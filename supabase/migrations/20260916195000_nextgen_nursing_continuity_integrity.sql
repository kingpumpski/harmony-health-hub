-- Next-generation inpatient continuity boundary.
-- Reuses canonical nursing_care_plans and nursing_shift_handovers; no duplicate tables/services.
-- Direct authenticated DML remains disabled. Lifecycle changes occur through locked RPCs.

-- The canonical handover table already owns shift_date/shift_label/pending_tasks/
-- safety_concerns. This migration adds only the missing admission relationship.
ALTER TABLE public.nursing_shift_handovers
  ADD COLUMN IF NOT EXISTS admission_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'nursing_shift_handovers_admission_id_fkey'
      AND conrelid = 'public.nursing_shift_handovers'::regclass
  ) THEN
    ALTER TABLE public.nursing_shift_handovers
      ADD CONSTRAINT nursing_shift_handovers_admission_id_fkey
      FOREIGN KEY (admission_id) REFERENCES public.admissions(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_nursing_handover_admission
  ON public.nursing_shift_handovers(admission_id, shift_date DESC, created_at DESC);

CREATE OR REPLACE FUNCTION public.create_nursing_care_plan(
  _patient_id UUID,
  _problem TEXT,
  _goal TEXT,
  _interventions TEXT,
  _priority TEXT DEFAULT 'routine',
  _encounter_id UUID DEFAULT NULL,
  _admission_id UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
  v_admission_status TEXT;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to create nursing care plans'; END IF;
  IF _patient_id IS NULL OR NULLIF(btrim(_problem), '') IS NULL OR NULLIF(btrim(_goal), '') IS NULL
     OR NULLIF(btrim(_interventions), '') IS NULL THEN
    RAISE EXCEPTION 'Patient, nursing problem, goal and interventions are required';
  END IF;
  IF _priority IS NULL OR _priority NOT IN ('routine','high','critical') THEN RAISE EXCEPTION 'Invalid nursing care-plan priority'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _admission_id IS NOT NULL THEN
    SELECT status INTO v_admission_status FROM public.admissions
    WHERE id = _admission_id AND patient_id = _patient_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Admission does not belong to patient'; END IF;
    IF v_admission_status <> 'admitted' THEN RAISE EXCEPTION 'Care plans can only be created for an active admission'; END IF;
  END IF;
  INSERT INTO public.nursing_care_plans(patient_id, encounter_id, admission_id, problem, goal, interventions, priority, created_by)
  VALUES (_patient_id, _encounter_id, _admission_id, btrim(_problem), btrim(_goal), btrim(_interventions), _priority, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_nursing_care_plan(
  _plan_id UUID, _status TEXT, _evaluation TEXT DEFAULT NULL, _reason TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_plan public.nursing_care_plans;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to transition nursing care plans'; END IF;
  IF _status IS NULL OR _status NOT IN ('active','on_hold','completed','cancelled') THEN RAISE EXCEPTION 'Invalid nursing care-plan status'; END IF;
  SELECT * INTO v_plan FROM public.nursing_care_plans WHERE id = _plan_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Nursing care plan not found'; END IF;
  IF v_plan.status IN ('completed','cancelled') AND _status IS DISTINCT FROM v_plan.status THEN RAISE EXCEPTION 'Closed nursing care plans cannot be reopened'; END IF;
  IF _status IN ('on_hold','cancelled') AND NULLIF(btrim(COALESCE(_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'A reason is required when a care plan is put on hold or cancelled'; END IF;
  IF _status = 'completed' AND NULLIF(btrim(COALESCE(_evaluation, '')), '') IS NULL THEN RAISE EXCEPTION 'Evaluation is required before completing a nursing care plan'; END IF;
  IF v_plan.admission_id IS NOT NULL AND _status = 'active' AND NOT EXISTS (
    SELECT 1 FROM public.admissions a WHERE a.id = v_plan.admission_id AND a.patient_id = v_plan.patient_id AND a.status = 'admitted'
  ) THEN RAISE EXCEPTION 'An active care plan cannot remain active after admission closure'; END IF;
  UPDATE public.nursing_care_plans SET status = _status,
    evaluation = CASE WHEN _status = 'completed' THEN NULLIF(btrim(_evaluation), '') ELSE evaluation END,
    updated_at = now() WHERE id = _plan_id;
  RETURN _plan_id;
END;
$$;

-- Preserve the established seven-argument handover function exactly as the canonical contract.
-- The admission-aware workflow is a separate overload and persists the canonical shift_date field.
CREATE OR REPLACE FUNCTION public.create_nursing_shift_handover(
  _patient_id UUID, _admission_id UUID, _shift_date DATE, _shift_name TEXT, _clinical_summary TEXT,
  _outstanding_tasks TEXT DEFAULT NULL, _risks_and_alerts TEXT DEFAULT NULL,
  _escalation_required BOOLEAN DEFAULT FALSE, _incoming_officer UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID; v_incoming UUID := COALESCE(_incoming_officer, auth.uid()); v_status TEXT;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to create nursing handovers'; END IF;
  IF _patient_id IS NULL OR NULLIF(btrim(_clinical_summary), '') IS NULL THEN RAISE EXCEPTION 'Patient and clinical summary are required'; END IF;
  IF _shift_date IS NULL OR NULLIF(btrim(_shift_name), '') IS NULL THEN RAISE EXCEPTION 'Shift date and shift name are required'; END IF;
  -- Permit legitimate late documentation of historical handovers, but reject dates materially ahead of the operational window.
  IF _shift_date > CURRENT_DATE + 1 THEN RAISE EXCEPTION 'Shift date cannot be more than one day in the future'; END IF;
  IF _admission_id IS NOT NULL THEN
    SELECT status INTO v_status FROM public.admissions WHERE id = _admission_id AND patient_id = _patient_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Admission does not belong to patient'; END IF;
    IF v_status <> 'admitted' THEN RAISE EXCEPTION 'Handover must reference an active admission'; END IF;
  END IF;
  IF _incoming_officer IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = _incoming_officer) THEN RAISE EXCEPTION 'Incoming officer not found'; END IF;
  IF _incoming_officer IS NOT NULL AND NOT (
    public.has_role(_incoming_officer,'admin') OR public.has_role(_incoming_officer,'nurse') OR
    public.has_role(_incoming_officer,'midwife') OR public.has_role(_incoming_officer,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Incoming officer must hold an authorized nursing role'; END IF;
  INSERT INTO public.nursing_shift_handovers(
    patient_id, admission_id, shift_date, outgoing_officer, incoming_officer, shift_label,
    clinical_summary, pending_tasks, safety_concerns, escalation_required
  ) VALUES (
    _patient_id, _admission_id, _shift_date, auth.uid(), v_incoming, btrim(_shift_name),
    btrim(_clinical_summary), NULLIF(btrim(_outstanding_tasks), ''), NULLIF(btrim(_risks_and_alerts), ''),
    COALESCE(_escalation_required, FALSE)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.acknowledge_nursing_shift_handover(_handover_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_handover public.nursing_shift_handovers;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to acknowledge nursing handovers'; END IF;
  SELECT * INTO v_handover FROM public.nursing_shift_handovers WHERE id = _handover_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Nursing handover not found'; END IF;
  IF v_handover.acknowledged_at IS NOT NULL THEN RETURN _handover_id; END IF;
  IF auth.uid() IS DISTINCT FROM v_handover.incoming_officer AND NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Only the designated incoming officer or an administrator can acknowledge this handover';
  END IF;
  UPDATE public.nursing_shift_handovers SET acknowledged_at = now() WHERE id = _handover_id;
  RETURN _handover_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_nursing_care_plan(UUID,TEXT,TEXT,TEXT,TEXT,UUID,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.transition_nursing_care_plan(UUID,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.transition_nursing_care_plan(UUID,TEXT,TEXT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.create_nursing_shift_handover(UUID,UUID,DATE,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_nursing_shift_handover(UUID,UUID,DATE,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.acknowledge_nursing_shift_handover(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.acknowledge_nursing_shift_handover(UUID) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.nursing_care_plans FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.nursing_shift_handovers FROM authenticated;

COMMENT ON TABLE public.nursing_care_plans IS 'Server-authoritative nursing care plans with locked lifecycle transitions and admission continuity checks.';
COMMENT ON TABLE public.nursing_shift_handovers IS 'Server-authoritative shift handover records with designated incoming-officer acknowledgement and optional admission linkage.';
COMMENT ON FUNCTION public.create_nursing_shift_handover(UUID,UUID,DATE,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) IS 'Admission-aware handover workflow; persists canonical shift_date, permits legitimate late documentation, and rejects materially future-dated handovers.';
