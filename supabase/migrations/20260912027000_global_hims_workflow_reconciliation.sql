-- Reconcile the global operational workflows with their UI contracts.
-- Additive/safe: preserve existing tables and data.

-- Nursing handover acknowledgement must be server-authoritative.
CREATE OR REPLACE FUNCTION public.acknowledge_nursing_handover(_handover_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); h public.nursing_shift_handovers%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  SELECT * INTO h FROM public.nursing_shift_handovers WHERE id=_handover_id FOR UPDATE;
  IF h.id IS NULL THEN RAISE EXCEPTION 'Handover not found'; END IF;
  IF h.acknowledged_at IS NOT NULL THEN RETURN jsonb_build_object('handover_id',_handover_id,'acknowledged_at',h.acknowledged_at); END IF;
  UPDATE public.nursing_shift_handovers SET incoming_officer=COALESCE(incoming_officer,uid), acknowledged_at=now() WHERE id=_handover_id;
  RETURN jsonb_build_object('handover_id',_handover_id,'acknowledged_at',now(),'incoming_officer',uid);
END; $$;
GRANT EXECUTE ON FUNCTION public.acknowledge_nursing_handover(UUID) TO authenticated;

-- Theatre status lifecycle is protected by role and row locking.
CREATE OR REPLACE FUNCTION public.transition_theatre_case(_case_id UUID, _status TEXT, _cancellation_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); c public.theatre_cases%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF _status NOT IN ('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN RAISE EXCEPTION 'Invalid theatre status'; END IF;
  SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
  IF c.status IN ('completed','cancelled') AND _status NOT IN ('completed','cancelled') THEN RAISE EXCEPTION 'Closed theatre case cannot be reopened'; END IF;
  UPDATE public.theatre_cases SET status=_status,
    cancellation_reason=CASE WHEN _status IN ('cancelled','postponed') THEN COALESCE(_cancellation_reason,cancellation_reason) ELSE cancellation_reason END,
    updated_at=now()
  WHERE id=_case_id;
  RETURN jsonb_build_object('case_id',_case_id,'status',_status);
END; $$;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(UUID,TEXT,TEXT) TO authenticated;

-- Claims UI uses _status; retain a single canonical transition contract.
DROP FUNCTION IF EXISTS public.transition_insurance_claim(UUID,TEXT,TEXT);
CREATE OR REPLACE FUNCTION public.transition_insurance_claim(_claim_id UUID, _status TEXT, _amount_approved NUMERIC DEFAULT NULL, _amount_paid NUMERIC DEFAULT NULL, _rejection_reason TEXT DEFAULT NULL, _notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.insurance_claims%ROWTYPE; uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Accounts role required'; END IF;
  IF _status NOT IN ('submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided') THEN RAISE EXCEPTION 'Invalid claim status'; END IF;
  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF c.status IN ('paid','voided') AND _status <> c.status THEN RAISE EXCEPTION 'Closed claim cannot change status'; END IF;
  IF _amount_approved IS NOT NULL AND _amount_approved < 0 THEN RAISE EXCEPTION 'Approved amount cannot be negative'; END IF;
  IF _amount_paid IS NOT NULL AND _amount_paid < 0 THEN RAISE EXCEPTION 'Paid amount cannot be negative'; END IF;
  IF _amount_approved IS NOT NULL AND _amount_approved > c.amount_claimed THEN RAISE EXCEPTION 'Approved amount exceeds claimed amount'; END IF;
  IF _amount_paid IS NOT NULL AND _amount_paid > COALESCE(_amount_approved,c.amount_approved,c.amount_claimed) THEN RAISE EXCEPTION 'Paid amount exceeds approved amount'; END IF;
  UPDATE public.insurance_claims SET status=_status,
    amount_approved=COALESCE(_amount_approved,amount_approved),
    amount_paid=COALESCE(_amount_paid,amount_paid),
    rejection_reason=CASE WHEN _status='rejected' THEN COALESCE(_rejection_reason,rejection_reason) ELSE rejection_reason END,
    submitted_at=CASE WHEN _status='submitted' AND submitted_at IS NULL THEN now() ELSE submitted_at END,
    adjudicated_at=CASE WHEN _status IN ('approved','partially_approved','rejected') THEN COALESCE(adjudicated_at,now()) ELSE adjudicated_at END,
    paid_at=CASE WHEN _status='paid' THEN COALESCE(paid_at,now()) ELSE paid_at END,
    updated_at=now()
  WHERE id=_claim_id;
  INSERT INTO public.insurance_claim_events(claim_id,event_type,from_status,to_status,notes,actor_id)
  VALUES (_claim_id,'status_changed',c.status,_status,_notes,uid);
  RETURN jsonb_build_object('claim_id',_claim_id,'status',_status,'amount_approved',COALESCE(_amount_approved,c.amount_approved),'amount_paid',COALESCE(_amount_paid,c.amount_paid));
END; $$;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;

-- Prevent direct client mutation of sensitive claim event history.
REVOKE INSERT, UPDATE, DELETE ON public.insurance_claim_events FROM authenticated;

-- The transition RPCs own operational mutations; clinical staff retain read access.
DROP POLICY IF EXISTS "transfusion clinical access" ON public.transfusion_records;
CREATE POLICY "transfusion clinical access" ON public.transfusion_records FOR SELECT TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse'));
CREATE POLICY "transfusion clinical insert" ON public.transfusion_records FOR INSERT TO authenticated
WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse'));

-- MAR writes should identify the administering actor only at administration time.
DROP POLICY IF EXISTS "mar clinical access" ON public.medication_administrations;
CREATE POLICY "mar clinical read" ON public.medication_administrations FOR SELECT TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'pharmacist'));
CREATE POLICY "mar clinical insert" ON public.medication_administrations FOR INSERT TO authenticated
WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'pharmacist'));
CREATE POLICY "mar clinical update" ON public.medication_administrations FOR UPDATE TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'pharmacist'))
WITH CHECK (administered_by IS NULL OR administered_by=auth.uid() OR public.has_role(auth.uid(),'admin'));
