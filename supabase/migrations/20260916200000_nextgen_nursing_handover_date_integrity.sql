-- Reconcile the admission-aware nursing handover contract with the canonical table.
-- The UI/RPC accepts an explicit shift date; persist it instead of silently
-- discarding the value. This is an additive field on the existing handover table,
-- not a replacement nursing table or service.

ALTER TABLE public.nursing_shift_handovers
  ADD COLUMN IF NOT EXISTS shift_date DATE NOT NULL DEFAULT CURRENT_DATE;

CREATE INDEX IF NOT EXISTS idx_nursing_handover_admission_shift_date
  ON public.nursing_shift_handovers(admission_id, shift_date DESC, created_at DESC);

CREATE OR REPLACE FUNCTION public.create_nursing_shift_handover(
  _patient_id UUID,
  _admission_id UUID,
  _shift_date DATE,
  _shift_name TEXT,
  _clinical_summary TEXT,
  _outstanding_tasks TEXT DEFAULT NULL,
  _risks_and_alerts TEXT DEFAULT NULL,
  _escalation_required BOOLEAN DEFAULT FALSE,
  _incoming_officer UUID DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id UUID;
  v_incoming UUID := COALESCE(_incoming_officer, auth.uid());
  v_status TEXT;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR
    public.has_role(auth.uid(),'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Not authorized to create nursing handovers';
  END IF;
  IF _patient_id IS NULL OR NULLIF(btrim(_clinical_summary), '') IS NULL THEN
    RAISE EXCEPTION 'Patient and clinical summary are required';
  END IF;
  IF _shift_date IS NULL OR NULLIF(btrim(_shift_name), '') IS NULL THEN
    RAISE EXCEPTION 'Shift date and shift name are required';
  END IF;
  IF _shift_date > CURRENT_DATE + 1 OR _shift_date < CURRENT_DATE - 1 THEN
    RAISE EXCEPTION 'Shift date is outside the allowed handover window';
  END IF;
  IF _admission_id IS NOT NULL THEN
    SELECT status INTO v_status
    FROM public.admissions
    WHERE id = _admission_id AND patient_id = _patient_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Admission does not belong to patient'; END IF;
    IF v_status <> 'admitted' THEN RAISE EXCEPTION 'Handover must reference an active admission'; END IF;
  END IF;
  IF _incoming_officer IS NOT NULL AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = _incoming_officer) THEN
    RAISE EXCEPTION 'Incoming officer not found';
  END IF;
  IF _incoming_officer IS NOT NULL AND NOT (
    public.has_role(_incoming_officer,'admin') OR
    public.has_role(_incoming_officer,'nurse') OR
    public.has_role(_incoming_officer,'midwife') OR
    public.has_role(_incoming_officer,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Incoming officer must hold an authorized nursing role';
  END IF;

  INSERT INTO public.nursing_shift_handovers(
    patient_id, admission_id, outgoing_officer, incoming_officer, shift_date,
    shift_label, clinical_summary, pending_tasks, safety_concerns, escalation_required
  ) VALUES (
    _patient_id, _admission_id, auth.uid(), v_incoming, _shift_date, btrim(_shift_name),
    btrim(_clinical_summary), NULLIF(btrim(_outstanding_tasks), ''),
    NULLIF(btrim(_risks_and_alerts), ''), COALESCE(_escalation_required, FALSE)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_nursing_shift_handover(UUID,UUID,DATE,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_nursing_shift_handover(UUID,UUID,DATE,TEXT,TEXT,TEXT,TEXT,BOOLEAN,UUID) TO authenticated;

COMMENT ON COLUMN public.nursing_shift_handovers.shift_date IS 'Clinical shift date supplied by the handover workflow; retained separately from record creation time.';
