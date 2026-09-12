-- Secure workflow extensions for nursing handover, theatre and insurance.

CREATE OR REPLACE FUNCTION public.acknowledge_nursing_handover(_handover_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); h public.nursing_shift_handovers%ROWTYPE;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
 SELECT * INTO h FROM public.nursing_shift_handovers WHERE id=_handover_id FOR UPDATE;
 IF h.id IS NULL THEN RAISE EXCEPTION 'Handover not found'; END IF;
 UPDATE public.nursing_shift_handovers SET incoming_officer=uid, acknowledged_at=now() WHERE id=_handover_id;
 RETURN jsonb_build_object('handover_id',_handover_id,'acknowledged_at',now(),'incoming_officer',uid);
END; $$;
GRANT EXECUTE ON FUNCTION public.acknowledge_nursing_handover(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.transition_theatre_case(_case_id UUID, _status TEXT, _cancellation_reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); c public.theatre_cases%ROWTYPE;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
 IF _status NOT IN ('requested','approved','scheduled','in_progress','completed','cancelled','postponed') THEN RAISE EXCEPTION 'Invalid theatre status'; END IF;
 SELECT * INTO c FROM public.theatre_cases WHERE id=_case_id FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Theatre case not found'; END IF;
 UPDATE public.theatre_cases SET status=_status, cancellation_reason=CASE WHEN _status IN ('cancelled','postponed') THEN _cancellation_reason ELSE cancellation_reason END WHERE id=_case_id;
 RETURN jsonb_build_object('case_id',_case_id,'status',_status);
END; $$;
GRANT EXECUTE ON FUNCTION public.transition_theatre_case(UUID,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.transition_insurance_claim(_claim_id UUID, _status TEXT, _amount_approved NUMERIC DEFAULT NULL, _amount_paid NUMERIC DEFAULT NULL, _rejection_reason TEXT DEFAULT NULL, _notes TEXT DEFAULT NULL)
RETURNS JSON LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); c public.insurance_claims%ROWTYPE; prev TEXT;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Accounts role required'; END IF;
 IF _status NOT IN ('draft','submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided') THEN RAISE EXCEPTION 'Invalid claim status'; END IF;
 SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'Insurance claim not found'; END IF;
 prev:=c.status;
 UPDATE public.insurance_claims SET status=_status, amount_approved=COALESCE(_amount_approved,amount_approved), amount_paid=COALESCE(_amount_paid,amount_paid), rejection_reason=CASE WHEN _status IN ('rejected','resubmission_required') THEN _rejection_reason ELSE rejection_reason END,
 submitted_at=CASE WHEN _status='submitted' AND submitted_at IS NULL THEN now() ELSE submitted_at END,
 adjudicated_at=CASE WHEN _status IN ('approved','partially_approved','rejected','resubmission_required') THEN now() ELSE adjudicated_at END,
 paid_at=CASE WHEN _status='paid' THEN now() ELSE paid_at END WHERE id=_claim_id;
 INSERT INTO public.insurance_claim_events(claim_id,event_type,from_status,to_status,notes,actor_id) VALUES (_claim_id,'status_change',prev,_status,_notes,uid);
 RETURN json_build_object('claim_id',_claim_id,'from_status',prev,'status',_status);
END; $$;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT) TO authenticated;
