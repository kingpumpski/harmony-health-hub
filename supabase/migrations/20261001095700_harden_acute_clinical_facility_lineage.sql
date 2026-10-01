-- Enforce patient/facility lineage at the database mutation boundary for acute clinical domains.
CREATE OR REPLACE FUNCTION public.enforce_clinical_facility_lineage()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE uid uuid := auth.uid(); patient_facility uuid; context_facility uuid;
BEGIN
  IF NEW.patient_id IS NULL THEN RAISE EXCEPTION 'Clinical record requires a patient'; END IF;
  SELECT p.facility_id INTO patient_facility FROM public.patients p WHERE p.id=NEW.patient_id FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
  IF NEW.facility_id IS NULL THEN NEW.facility_id := patient_facility;
  ELSIF NEW.facility_id IS DISTINCT FROM patient_facility THEN RAISE EXCEPTION 'Clinical record facility does not match patient facility'; END IF;
  IF uid IS NOT NULL AND NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    context_facility := public.current_user_facility_id();
    IF context_facility IS NULL OR context_facility IS DISTINCT FROM patient_facility THEN RAISE EXCEPTION 'Clinical record belongs to a different facility context'; END IF;
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.enforce_ai_clinical_event_facility()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE uid uuid := auth.uid(); session_facility uuid; context_facility uuid;
BEGIN
  SELECT s.facility_id INTO session_facility FROM public.ai_clinical_sessions s WHERE s.id=NEW.session_id;
  IF NOT FOUND OR session_facility IS NULL THEN RAISE EXCEPTION 'AI clinical session facility attribution is unresolved'; END IF;
  IF uid IS NOT NULL AND NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    context_facility := public.current_user_facility_id();
    IF context_facility IS NULL OR context_facility IS DISTINCT FROM session_facility THEN RAISE EXCEPTION 'AI clinical event belongs to a different facility context'; END IF;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_enforce_imaging_facility_lineage ON public.imaging_orders;
CREATE TRIGGER trg_enforce_imaging_facility_lineage BEFORE INSERT OR UPDATE OF patient_id,facility_id ON public.imaging_orders FOR EACH ROW EXECUTE FUNCTION public.enforce_clinical_facility_lineage();
DROP TRIGGER IF EXISTS trg_enforce_emergency_facility_lineage ON public.emergency_cases;
CREATE TRIGGER trg_enforce_emergency_facility_lineage BEFORE INSERT OR UPDATE OF patient_id,facility_id ON public.emergency_cases FOR EACH ROW EXECUTE FUNCTION public.enforce_clinical_facility_lineage();
DROP TRIGGER IF EXISTS trg_enforce_theatre_facility_lineage ON public.theatre_cases;
CREATE TRIGGER trg_enforce_theatre_facility_lineage BEFORE INSERT OR UPDATE OF patient_id,facility_id ON public.theatre_cases FOR EACH ROW EXECUTE FUNCTION public.enforce_clinical_facility_lineage();
DROP TRIGGER IF EXISTS trg_enforce_transfusion_facility_lineage ON public.transfusion_records;
CREATE TRIGGER trg_enforce_transfusion_facility_lineage BEFORE INSERT OR UPDATE OF patient_id,facility_id ON public.transfusion_records FOR EACH ROW EXECUTE FUNCTION public.enforce_clinical_facility_lineage();
DROP TRIGGER IF EXISTS trg_enforce_admission_facility_lineage ON public.admissions;
CREATE TRIGGER trg_enforce_admission_facility_lineage BEFORE INSERT OR UPDATE OF patient_id,facility_id ON public.admissions FOR EACH ROW EXECUTE FUNCTION public.enforce_clinical_facility_lineage();
DROP TRIGGER IF EXISTS trg_enforce_ai_session_facility_lineage ON public.ai_clinical_sessions;
CREATE TRIGGER trg_enforce_ai_session_facility_lineage BEFORE INSERT OR UPDATE OF patient_id,facility_id ON public.ai_clinical_sessions FOR EACH ROW EXECUTE FUNCTION public.enforce_clinical_facility_lineage();
DROP TRIGGER IF EXISTS trg_enforce_ai_event_facility_lineage ON public.ai_clinical_events;
CREATE TRIGGER trg_enforce_ai_event_facility_lineage BEFORE INSERT OR UPDATE OF session_id ON public.ai_clinical_events FOR EACH ROW EXECUTE FUNCTION public.enforce_ai_clinical_event_facility();
REVOKE ALL ON FUNCTION public.enforce_clinical_facility_lineage() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.enforce_ai_clinical_event_facility() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enforce_clinical_facility_lineage() TO authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_ai_clinical_event_facility() TO authenticated;
