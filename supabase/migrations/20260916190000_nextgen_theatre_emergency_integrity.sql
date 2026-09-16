-- Next-generation theatre/emergency integrity boundary.
-- Reconciles the earlier lifecycle RPCs with the canonical table columns and adds
-- server-authoritative concurrency/state-transition controls without new tables.

CREATE OR REPLACE FUNCTION public.create_theatre_case(
  _patient_id uuid,
  _procedure_name text,
  _scheduled_start timestamptz DEFAULT NULL,
  _theatre_name text DEFAULT NULL,
  _urgency text DEFAULT 'elective',
  _surgeon_id uuid DEFAULT NULL,
  _anesthetist_id uuid DEFAULT NULL,
  _encounter_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_patient uuid;
  v_status text;
  v_start timestamptz := _scheduled_start;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
  ) THEN RAISE EXCEPTION 'Not authorized to create theatre cases'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_procedure_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and procedure are required';
  END IF;
  IF _urgency NOT IN ('emergency','urgent','elective') THEN RAISE EXCEPTION 'Invalid theatre urgency'; END IF;
  IF _encounter_id IS NOT NULL THEN
    SELECT patient_id,status INTO v_patient,v_status FROM public.encounters WHERE id=_encounter_id;
    IF NOT FOUND OR v_patient<>_patient_id THEN RAISE EXCEPTION 'Encounter does not belong to the selected patient'; END IF;
    IF v_status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Cannot create a theatre case for a closed encounter'; END IF;
  END IF;
  IF v_start IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(_patient_id::text || '|' || date_trunc('minute',v_start)::text,0));
    IF EXISTS (
      SELECT 1 FROM public.theatre_cases t
      WHERE t.patient_id=_patient_id
        AND t.scheduled_start=v_start
        AND t.status NOT IN ('completed','cancelled','postponed')
    ) THEN RAISE EXCEPTION 'Conflicting active theatre case exists for this patient and start time'; END IF;
  END IF;
  INSERT INTO public.theatre_cases(
    patient_id,encounter_id,procedure_name,surgeon_id,anesthetist_id,scheduled_start,
    theatre_name,urgency,status,created_by
  ) VALUES (
    _patient_id,_encounter_id,trim(_procedure_name),_surgeon_id,_anesthetist_id,v_start,
    NULLIF(trim(COALESCE(_theatre_name,'')),''),_urgency,'requested',uid
  ) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_theatre_case(
  _case_id uuid,
  _status text,
  _cancellation_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  uid uuid := auth.uid();
  c public.theatre_cases%ROWTYPE;
  encounter_status text;
  allowed boolean := false;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
  ) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _status NOT IN ('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN
    RAISE EXCEPTION 'Invalid theatre status';
  END IF;
  SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Theatre case not found'; END IF;

  allowed := CASE c.status
    WHEN 'requested' THEN _status IN ('requested','approved','cancelled')
    WHEN 'approved' THEN _status IN ('approved','scheduled','cancelled','postponed')
    WHEN 'scheduled' THEN _status IN ('scheduled','in_progress','cancelled','postponed')
    WHEN 'in_progress' THEN _status IN ('in_progress','completed','cancelled')
    WHEN 'completed' THEN _status='completed'
    WHEN 'cancelled' THEN _status='cancelled'
    WHEN 'postponed' THEN _status IN ('postponed','scheduled','cancelled')
    ELSE false
  END;
  IF NOT allowed THEN RAISE EXCEPTION 'Invalid theatre state transition from % to %',c.status,_status; END IF;

  IF c.encounter_id IS NOT NULL THEN
    SELECT status INTO encounter_status FROM public.encounters WHERE id=c.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF encounter_status='cancelled' AND _status NOT IN ('cancelled','completed') THEN
      RAISE EXCEPTION 'Cannot progress theatre case for a cancelled encounter';
    END IF;
    IF encounter_status='completed' AND _status NOT IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot progress theatre case for a completed encounter';
    END IF;
  END IF;

  IF _status IN ('cancelled','postponed') AND NULLIF(trim(COALESCE(_cancellation_reason,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Reason is required when cancelling or postponing a theatre case';
  END IF;

  UPDATE public.theatre_cases
  SET status=_status,
      cancellation_reason=CASE WHEN _status IN ('cancelled','postponed') THEN trim(_cancellation_reason) ELSE cancellation_reason END,
      updated_at=now()
  WHERE id=_case_id;

  RETURN jsonb_build_object('case_id',_case_id,'from_status',c.status,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.transition_emergency_case(
  _case_id uuid,
  _status text,
  _disposition text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  uid uuid := auth.uid();
  c public.emergency_cases%ROWTYPE;
  allowed boolean := false;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
  ) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _status NOT IN ('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled') THEN
    RAISE EXCEPTION 'Invalid emergency status';
  END IF;
  SELECT * INTO c FROM public.emergency_cases WHERE id=_case_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Emergency case not found'; END IF;

  allowed := CASE c.status
    WHEN 'waiting' THEN _status IN ('waiting','triage','left_without_being_seen','cancelled')
    WHEN 'triage' THEN _status IN ('triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled')
    WHEN 'treatment' THEN _status IN ('treatment','observation','admitted','discharged','referred','cancelled')
    WHEN 'observation' THEN _status IN ('observation','treatment','admitted','discharged','referred','cancelled')
    WHEN 'admitted' THEN _status IN ('admitted','discharged','cancelled')
    WHEN 'discharged' THEN _status='discharged'
    WHEN 'referred' THEN _status='referred'
    WHEN 'left_without_being_seen' THEN _status='left_without_being_seen'
    WHEN 'cancelled' THEN _status='cancelled'
    ELSE false
  END;
  IF NOT allowed THEN RAISE EXCEPTION 'Invalid emergency state transition from % to %',c.status,_status; END IF;

  IF _status IN ('discharged','referred','left_without_being_seen')
     AND NULLIF(trim(COALESCE(_disposition,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Disposition is required for terminal emergency outcome';
  END IF;

  UPDATE public.emergency_cases
  SET status=_status,
      disposition=CASE WHEN NULLIF(trim(COALESCE(_disposition,'')),'') IS NOT NULL THEN trim(_disposition) ELSE disposition END,
      disposition_at=CASE WHEN _status IN ('discharged','referred','left_without_being_seen','cancelled') THEN COALESCE(disposition_at,now()) ELSE disposition_at END,
      assigned_officer=COALESCE(assigned_officer,uid),
      updated_at=now()
  WHERE id=_case_id;

  RETURN jsonb_build_object('case_id',_case_id,'from_status',c.status,'status',_status);
END; $$;

REVOKE ALL ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_theatre_case(uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.transition_emergency_case(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_emergency_case(uuid,text,text) TO authenticated;

COMMENT ON FUNCTION public.create_theatre_case(uuid,text,timestamptz,text,text,uuid,uuid,uuid) IS
'Server-authoritative theatre creation; uses canonical theatre_cases columns and concurrency protection.';
COMMENT ON FUNCTION public.transition_theatre_case(uuid,text,text) IS
'Server-authoritative theatre state machine with row locking and closed-state protection.';
COMMENT ON FUNCTION public.transition_emergency_case(uuid,text,text) IS
'Server-authoritative emergency state machine with row locking and terminal disposition requirements.';
