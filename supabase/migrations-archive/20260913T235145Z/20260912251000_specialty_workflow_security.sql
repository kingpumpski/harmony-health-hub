-- Specialty clinical workflow hardening.
-- Keep high-value clinical documentation behind SECURITY DEFINER RPCs so the
-- authenticated PostgREST role cannot bypass role checks or future audit hooks.

CREATE OR REPLACE FUNCTION public.create_dental_record(
  _patient_id UUID,
  _examination TEXT,
  _treatment_plan TEXT,
  _procedures_performed TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'practitioner')) THEN RAISE EXCEPTION 'Authorized clinical role required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  INSERT INTO public.dental_records (patient_id, examination, treatment_plan, procedures_performed, performed_by)
  VALUES (_patient_id, NULLIF(trim(_examination), ''), NULLIF(trim(_treatment_plan), ''), NULLIF(trim(_procedures_performed), ''), auth.uid())
  RETURNING id INTO _id;
  RETURN _id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_procedure_note(
  _patient_id UUID,
  _procedure_name TEXT,
  _template_used TEXT,
  _indication TEXT,
  _technique TEXT,
  _findings TEXT,
  _complications TEXT,
  _post_op_plan TEXT,
  _charge_amount NUMERIC,
  _service_order_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'practitioner') OR public.has_role(auth.uid(), 'nurse') OR public.has_role(auth.uid(), 'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF COALESCE(_charge_amount, 0) > 0 THEN
    IF _service_order_id IS NULL THEN RAISE EXCEPTION 'A released service order is required for a chargeable procedure'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.service_orders WHERE id = _service_order_id AND patient_id = _patient_id AND status IN ('released', 'in_progress', 'completed')) THEN RAISE EXCEPTION 'Procedure payment has not been released'; END IF;
  END IF;
  INSERT INTO public.procedure_notes (patient_id, procedure_name, template_used, indication, technique, findings, complications, post_op_plan, performed_by, status, charge_amount, service_order_id)
  VALUES (_patient_id, NULLIF(trim(_procedure_name), ''), NULLIF(trim(_template_used), ''), NULLIF(trim(_indication), ''), NULLIF(trim(_technique), ''), NULLIF(trim(_findings), ''), NULLIF(trim(_complications), ''), NULLIF(trim(_post_op_plan), ''), auth.uid(), 'completed', GREATEST(COALESCE(_charge_amount, 0), 0), _service_order_id)
  RETURNING id INTO _id;
  RETURN _id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_dental_record(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_procedure_note(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_dental_record(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_procedure_note(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, UUID) TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.dental_records FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.procedure_notes FROM authenticated;
GRANT SELECT ON public.dental_records, public.procedure_notes TO authenticated;
