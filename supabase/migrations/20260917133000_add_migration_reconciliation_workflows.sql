-- Controlled reconciliation layer for imported legacy clinical records.
-- Matching is explicit; no legacy record is promoted into native clinical tables automatically.

ALTER TABLE public.legacy_clinical_records
  ADD COLUMN IF NOT EXISTS match_confidence NUMERIC(5,4),
  ADD COLUMN IF NOT EXISTS match_method TEXT,
  ADD COLUMN IF NOT EXISTS validation_errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS reconciled_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_legacy_records_reconciliation
  ON public.legacy_clinical_records(migration_status,match_confidence,occurred_at DESC);

CREATE OR REPLACE FUNCTION public.find_legacy_patient_candidates(_record_id UUID)
RETURNS TABLE(patient_id UUID, patient_code TEXT, first_name TEXT, last_name TEXT, date_of_birth DATE, match_method TEXT, match_confidence NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_record public.legacy_clinical_records;
  v_phone TEXT;
  v_email TEXT;
  v_dob DATE;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  SELECT * INTO v_record FROM public.legacy_clinical_records WHERE id=_record_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Legacy record not found'; END IF;

  v_phone := NULLIF(regexp_replace(COALESCE(v_record.raw_record->>'phone',v_record.raw_record->>'mobile',v_record.raw_record->>'telephone',''),'[^0-9+]','','g'),'');
  v_email := NULLIF(lower(trim(COALESCE(v_record.raw_record->>'email',v_record.raw_record->>'email_address',''))),'');
  BEGIN v_dob := NULLIF(v_record.raw_record->>'date_of_birth','')::date; EXCEPTION WHEN others THEN v_dob := NULL; END;

  RETURN QUERY
  SELECT p.id,p.patient_code,p.first_name,p.last_name,p.date_of_birth,
    CASE
      WHEN v_record.source_patient_key IS NOT NULL AND lower(trim(p.patient_code))=lower(trim(v_record.source_patient_key)) THEN 'source_patient_key'
      WHEN v_phone IS NOT NULL AND regexp_replace(COALESCE(p.phone,''),'[^0-9+]','','g')=v_phone AND v_dob IS NOT NULL AND p.date_of_birth=v_dob THEN 'phone_and_dob'
      WHEN v_email IS NOT NULL AND lower(trim(COALESCE(p.email,'')))=v_email AND v_dob IS NOT NULL AND p.date_of_birth=v_dob THEN 'email_and_dob'
      WHEN v_dob IS NOT NULL AND p.date_of_birth=v_dob AND lower(trim(p.first_name))=lower(trim(COALESCE(v_record.raw_record->>'first_name',v_record.raw_record->>'given_name',''))) AND lower(trim(p.last_name))=lower(trim(COALESCE(v_record.raw_record->>'last_name',v_record.raw_record->>'surname',''))) THEN 'name_and_dob'
      ELSE 'candidate'
    END,
    CASE
      WHEN v_record.source_patient_key IS NOT NULL AND lower(trim(p.patient_code))=lower(trim(v_record.source_patient_key)) THEN 1.0000
      WHEN v_phone IS NOT NULL AND regexp_replace(COALESCE(p.phone,''),'[^0-9+]','','g')=v_phone AND v_dob IS NOT NULL AND p.date_of_birth=v_dob THEN 0.9800
      WHEN v_email IS NOT NULL AND lower(trim(COALESCE(p.email,'')))=v_email AND v_dob IS NOT NULL AND p.date_of_birth=v_dob THEN 0.9800
      WHEN v_dob IS NOT NULL AND p.date_of_birth=v_dob AND lower(trim(p.first_name))=lower(trim(COALESCE(v_record.raw_record->>'first_name',v_record.raw_record->>'given_name',''))) AND lower(trim(p.last_name))=lower(trim(COALESCE(v_record.raw_record->>'last_name',v_record.raw_record->>'surname',''))) THEN 0.9500
      ELSE 0.5000
    END
  FROM public.patients p
  WHERE (v_record.source_patient_key IS NOT NULL AND lower(trim(p.patient_code))=lower(trim(v_record.source_patient_key)))
     OR (v_phone IS NOT NULL AND regexp_replace(COALESCE(p.phone,''),'[^0-9+]','','g')=v_phone)
     OR (v_email IS NOT NULL AND lower(trim(COALESCE(p.email,'')))=v_email)
     OR (v_dob IS NOT NULL AND p.date_of_birth=v_dob AND lower(trim(p.first_name))=lower(trim(COALESCE(v_record.raw_record->>'first_name',v_record.raw_record->>'given_name',''))) AND lower(trim(p.last_name))=lower(trim(COALESCE(v_record.raw_record->>'last_name',v_record.raw_record->>'surname',''))))
  ORDER BY match_confidence DESC, p.created_at DESC
  LIMIT 25;
END; $$;

CREATE OR REPLACE FUNCTION public.reconcile_legacy_record_patient(_record_id UUID,_patient_id UUID,_method TEXT DEFAULT 'manual')
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_record public.legacy_clinical_records; v_patient public.patients;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  SELECT * INTO v_record FROM public.legacy_clinical_records WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Legacy record not found'; END IF;
  SELECT * INTO v_patient FROM public.patients WHERE id=_patient_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found'; END IF;
  UPDATE public.legacy_clinical_records
  SET patient_id=_patient_id,migration_status='matched',match_method=COALESCE(NULLIF(trim(_method),''),'manual'),match_confidence=CASE WHEN lower(COALESCE(_method,''))='manual' THEN 1.0000 ELSE match_confidence END,reconciled_by=auth.uid(),reconciled_at=now()
  WHERE id=_record_id;
  RETURN TRUE;
END; $$;

CREATE OR REPLACE FUNCTION public.validate_legacy_record(_record_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_record public.legacy_clinical_records; v_errors JSONB := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  SELECT * INTO v_record FROM public.legacy_clinical_records WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Legacy record not found'; END IF;
  IF v_record.record_type IS NULL OR trim(v_record.record_type)='' THEN v_errors := v_errors || jsonb_build_array('record_type is required'); END IF;
  IF v_record.source_system IS NULL OR trim(v_record.source_system)='' THEN v_errors := v_errors || jsonb_build_array('source_system is required'); END IF;
  IF v_record.occurred_at IS NULL THEN v_errors := v_errors || jsonb_build_array('occurred_at is required for chronology validation'); END IF;
  IF v_record.patient_id IS NULL THEN v_errors := v_errors || jsonb_build_array('patient matching is required before promotion'); END IF;
  IF jsonb_array_length(v_errors)=0 THEN
    UPDATE public.legacy_clinical_records SET migration_status='matched',validation_errors='[]'::jsonb WHERE id=_record_id;
  ELSE
    UPDATE public.legacy_clinical_records SET migration_status='needs_review',validation_errors=v_errors WHERE id=_record_id;
  END IF;
  RETURN v_errors;
END; $$;

REVOKE ALL ON FUNCTION public.find_legacy_patient_candidates(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.find_legacy_patient_candidates(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.reconcile_legacy_record_patient(UUID,UUID,TEXT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reconcile_legacy_record_patient(UUID,UUID,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.validate_legacy_record(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.validate_legacy_record(UUID) TO authenticated;
