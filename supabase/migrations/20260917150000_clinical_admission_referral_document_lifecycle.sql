-- Harmony Health Hub: clinical admission override, specialist referral scheduling,
-- and governed draft -> submit -> version lifecycle foundation.
-- Forward-only. Do not apply directly to production without the approved migration process.

ALTER TABLE public.facility_settings
  ADD COLUMN IF NOT EXISTS allow_treatment_before_deposit BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS admission_financial_override_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS require_accounts_release_after_deposit BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS allow_clinical_emergency_override BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public.encounters
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS submitted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS version_no INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS admission_id UUID REFERENCES public.admissions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_encounters_document_lifecycle
  ON public.encounters(status, practitioner_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.document_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  version_no INTEGER NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('saved','submitted','reopened')),
  snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(entity_type, entity_id, version_no, action)
);
CREATE INDEX IF NOT EXISTS idx_document_versions_entity
  ON public.document_versions(entity_type, entity_id, changed_at DESC);
ALTER TABLE public.document_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "document versions staff read" ON public.document_versions;
CREATE POLICY "document versions staff read" ON public.document_versions
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin')
    OR changed_by = auth.uid()
    OR public.is_clinical_staff(auth.uid())
  );
GRANT SELECT ON public.document_versions TO authenticated;
GRANT ALL ON public.document_versions TO service_role;

CREATE OR REPLACE FUNCTION public.reopen_own_document(
  _entity_type TEXT,
  _entity_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_status TEXT;
  v_owner UUID;
  v_version INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _entity_type = 'encounter' THEN
    SELECT status, practitioner_id, version_no INTO v_status, v_owner, v_version
    FROM public.encounters WHERE id = _entity_id FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Document not found'; END IF;
  ELSE
    RAISE EXCEPTION 'Unsupported document type';
  END IF;
  IF v_owner <> auth.uid() AND NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Only the document creator can reopen this document';
  END IF;
  IF v_status <> 'completed' THEN
    RAISE EXCEPTION 'Only submitted documents can be reopened';
  END IF;
  UPDATE public.encounters
  SET status='draft', locked_at=NULL, submitted_at=NULL, submitted_by=NULL,
      version_no=v_version+1, updated_at=now()
  WHERE id=_entity_id;
  PERFORM public.record_system_audit(
    'document_reopened','clinical','encounter',_entity_id,'warning',
    jsonb_build_object('previous_version',v_version,'new_version',v_version+1)
  );
  INSERT INTO public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  VALUES('encounter',_entity_id,v_version+1,'reopened',jsonb_build_object('previous_version',v_version),auth.uid());
  RETURN jsonb_build_object('entity_id',_entity_id,'version_no',v_version+1,'status','draft');
END; $$;

REVOKE ALL ON FUNCTION public.reopen_own_document(TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reopen_own_document(TEXT,UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_encounter_workflow(
  _encounter_id UUID,
  _specialty TEXT DEFAULT NULL,
  _appointment_date TIMESTAMPTZ DEFAULT NULL,
  _referral_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_enc public.encounters%ROWTYPE;
  v_referral UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  IF v_enc.practitioner_id <> auth.uid() AND NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Only the encounter creator can submit this document';
  END IF;
  IF v_enc.status = 'completed' THEN RAISE EXCEPTION 'Encounter is already submitted'; END IF;
  IF NULLIF(btrim(_specialty),'') IS NOT NULL THEN
    IF _appointment_date IS NULL THEN RAISE EXCEPTION 'Referral appointment date is required'; END IF;
    INSERT INTO public.patient_referrals(
      patient_id, encounter_id, referred_by, destination, specialty, reason,
      urgency, status, clinical_summary, appointment_date
    ) VALUES (
      v_enc.patient_id, v_enc.id, auth.uid(), 'Specialist Clinic',
      btrim(_specialty), COALESCE(NULLIF(btrim(_referral_reason),''),'Specialist review requested'),
      'routine', 'requested', COALESCE(v_enc.treatment_plan,v_enc.principal_diagnosis), _appointment_date
    ) RETURNING id INTO v_referral;
  END IF;
  UPDATE public.encounters
  SET status='completed', submitted_at=now(), submitted_by=auth.uid(), locked_at=now(), updated_at=now()
  WHERE id=_encounter_id;
  INSERT INTO public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  VALUES('encounter',v_enc.id,v_enc.version_no,'submitted',
    jsonb_build_object('patient_id',v_enc.patient_id,'principal_diagnosis',v_enc.principal_diagnosis,
      'treatment_plan',v_enc.treatment_plan,'referral_id',v_referral),auth.uid());
  PERFORM public.record_system_audit(
    'encounter_submitted','clinical','encounter',v_enc.id,'info',
    jsonb_build_object('patient_id',v_enc.patient_id,'version_no',v_enc.version_no,'referral_id',v_referral)
  );
  RETURN jsonb_build_object('encounter_id',v_enc.id,'status','completed','version_no',v_enc.version_no,'referral_id',v_referral);
END; $$;

REVOKE ALL ON FUNCTION public.submit_encounter_workflow(UUID,TEXT,TIMESTAMPTZ,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_encounter_workflow(UUID,TEXT,TIMESTAMPTZ,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admit_encounter_workflow(
  _encounter_id UUID,
  _reason TEXT DEFAULT NULL,
  _ward TEXT DEFAULT NULL,
  _emergency_override BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_enc public.encounters%ROWTYPE;
  v_admission UUID;
  v_override BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Admission is not permitted for this role';
  END IF;
  SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  IF v_enc.status <> 'completed' THEN RAISE EXCEPTION 'Submit the encounter before admission'; END IF;
  IF v_enc.admission_id IS NOT NULL THEN
    RETURN jsonb_build_object('admission_id',v_enc.admission_id,'override',FALSE,'existing',TRUE);
  END IF;
  SELECT allow_treatment_before_deposit AND admission_financial_override_enabled
    INTO v_override FROM public.facility_settings WHERE id='default';
  v_override := COALESCE(v_override,FALSE) AND COALESCE(_emergency_override,TRUE);

  INSERT INTO public.admissions(patient_id,encounter_id,ward,reason,admitted_by,status)
  VALUES(v_enc.patient_id,v_enc.id,NULLIF(btrim(_ward),''),COALESCE(NULLIF(btrim(_reason),''),'Clinical admission'),auth.uid(),'admitted')
  RETURNING id INTO v_admission;

  UPDATE public.encounters SET admission_id=v_admission, updated_at=now() WHERE id=v_enc.id;

  IF v_override THEN
    UPDATE public.service_orders
    SET status='released', approved_by=auth.uid(), approved_at=now(), updated_at=now(),
        notes=concat_ws(E'\n',notes,'Emergency admission financial override: treatment released before deposit.')
    WHERE encounter_id=v_enc.id AND status IN ('pending_payment','pending_payment_approval');
    PERFORM public.record_system_audit(
      'admission_financial_override','admissions','admission',v_admission,'critical',
      jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'override',TRUE)
    );
  END IF;
  PERFORM public.record_system_audit(
    'patient_admitted','admissions','admission',v_admission,'info',
    jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'financial_override',v_override)
  );
  RETURN jsonb_build_object('admission_id',v_admission,'override',v_override,'status','admitted');
END; $$;

REVOKE ALL ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pending_specialist_referrals()
RETURNS TABLE(
  referral_id UUID, patient_id UUID, patient_name TEXT, telephone TEXT,
  specialty TEXT, appointment_date TIMESTAMPTZ, referred_at TIMESTAMPTZ, status TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT r.id,r.patient_id,concat(p.first_name,' ',p.last_name),p.phone,r.specialty,
         r.appointment_date,r.created_at,r.status
  FROM public.patient_referrals r
  JOIN public.patients p ON p.id=r.patient_id
  WHERE r.status IN ('requested','accepted','scheduled')
    AND r.specialty IS NOT NULL
  ORDER BY r.appointment_date NULLS LAST,r.created_at ASC;
$$;
REVOKE ALL ON FUNCTION public.get_pending_specialist_referrals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_pending_specialist_referrals() TO authenticated;
