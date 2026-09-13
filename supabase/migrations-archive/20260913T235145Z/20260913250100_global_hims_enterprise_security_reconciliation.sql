-- Canonical enterprise HIMS security reconciliation.
-- Server-authoritative writes remain protected by role-aware RPCs where applicable.

DROP POLICY IF EXISTS "clinical operations read" ON public.wards;
CREATE POLICY "clinical operations read" ON public.wards FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'front_desk'));
DROP POLICY IF EXISTS "clinical operations read beds" ON public.beds;
CREATE POLICY "clinical operations read beds" ON public.beds FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'front_desk'));
DROP POLICY IF EXISTS "clinical operations manage" ON public.beds;
CREATE POLICY "clinical operations manage" ON public.beds FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse'));
DROP POLICY IF EXISTS "nursing care plans clinical" ON public.nursing_care_plans;
CREATE POLICY "nursing care plans clinical" ON public.nursing_care_plans FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife'));
DROP POLICY IF EXISTS "handover clinical" ON public.nursing_shift_handovers;
CREATE POLICY "handover clinical" ON public.nursing_shift_handovers FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife'));
DROP POLICY IF EXISTS "emergency clinical" ON public.emergency_cases;
CREATE POLICY "emergency clinical" ON public.emergency_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'front_desk')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'front_desk'));
DROP POLICY IF EXISTS "theatre clinical" ON public.theatre_cases;
CREATE POLICY "theatre clinical" ON public.theatre_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse'));
DROP POLICY IF EXISTS "transfusion clinical" ON public.transfusion_records;
CREATE POLICY "transfusion clinical" ON public.transfusion_records FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse'));
DROP POLICY IF EXISTS "insurance clinical accounts" ON public.insurance_cases;
CREATE POLICY "insurance clinical accounts" ON public.insurance_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'accountant')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'accountant'));

CREATE OR REPLACE FUNCTION public.update_insurance_case(_id UUID,_eligibility TEXT,_authorization TEXT,_claim_status TEXT,_claim_amount NUMERIC,_approved_amount NUMERIC,_rejection_reason TEXT)
RETURNS public.insurance_cases LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.insurance_cases;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF _eligibility NOT IN ('unknown','eligible','ineligible','pending','expired') THEN RAISE EXCEPTION 'Invalid eligibility status'; END IF;
  IF _claim_status NOT IN ('not_submitted','draft','submitted','under_review','approved','partially_approved','rejected','paid','appealed') THEN RAISE EXCEPTION 'Invalid claim status'; END IF;
  UPDATE public.insurance_cases SET eligibility_status=_eligibility,eligibility_checked_at=CASE WHEN _eligibility<>'unknown' THEN now() ELSE eligibility_checked_at END,authorization_number=_authorization,claim_status=_claim_status,claim_amount=GREATEST(COALESCE(_claim_amount,0),0),approved_amount=GREATEST(COALESCE(_approved_amount,0),0),rejection_reason=_rejection_reason,checked_by=auth.uid(),updated_at=now() WHERE id=_id RETURNING * INTO v;
  IF NOT FOUND THEN RAISE EXCEPTION 'Insurance case not found'; END IF;
  RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.update_insurance_case(UUID,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,TEXT) FROM anon,PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_insurance_case(UUID,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,TEXT) TO authenticated;
NOTIFY pgrst,'reload schema';
