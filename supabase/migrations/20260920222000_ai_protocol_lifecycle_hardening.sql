-- Server-authoritative AI protocol lifecycle. Generated protocols remain pending review.

CREATE OR REPLACE FUNCTION public.transition_ai_protocol(_protocol_id uuid, _status text)
RETURNS public.ai_protocols
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_row public.ai_protocols; v_status text := lower(btrim(_status));
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Not authorised'; END IF;
  IF v_status NOT IN ('pending_review','approved','rejected','archived') THEN RAISE EXCEPTION 'Invalid protocol status'; END IF;
  SELECT * INTO v_row FROM public.ai_protocols WHERE id=_protocol_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Protocol not found'; END IF;
  IF v_row.status IN ('approved','rejected','archived') AND v_status <> v_row.status THEN RAISE EXCEPTION 'Terminal protocol status cannot be changed'; END IF;
  IF v_status='approved' AND v_row.status <> 'pending_review' THEN RAISE EXCEPTION 'Only pending protocols can be approved'; END IF;
  IF v_status='rejected' AND v_row.status <> 'pending_review' THEN RAISE EXCEPTION 'Only pending protocols can be rejected'; END IF;
  UPDATE public.ai_protocols SET status=v_status, approved_by=CASE WHEN v_status='approved' THEN auth.uid() ELSE approved_by END, approved_at=CASE WHEN v_status='approved' THEN now() ELSE approved_at END WHERE id=_protocol_id RETURNING * INTO v_row;
  RETURN v_row;
END; $$;

REVOKE ALL ON FUNCTION public.transition_ai_protocol(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.transition_ai_protocol(uuid,text) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.ai_protocols FROM authenticated;
