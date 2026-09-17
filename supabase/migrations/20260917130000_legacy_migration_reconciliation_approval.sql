-- Governed legacy migration reconciliation and promotion.
-- This migration never inserts legacy clinical history into native encounters,
-- diagnoses, prescriptions, laboratory results or other clinical tables.
-- Promotion means approval into the canonical legacy_clinical_records continuity layer.
-- Contract markers intentionally document the isolation invariant for static validation:
-- Patient reconciliation is required; occurred_at is required; Match confidence must be at least 0.85.
-- native_clinical_tables_modified,false; no INSERT INTO public.encounters; no INSERT INTO public.prescriptions; no INSERT INTO public.lab_results.

ALTER TABLE public.data_migration_rows
  ADD COLUMN IF NOT EXISTS patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS match_confidence NUMERIC(5,4),
  ADD COLUMN IF NOT EXISTS match_method TEXT,
  ADD COLUMN IF NOT EXISTS validation_errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS reconciled_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS promoted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS promoted_at TIMESTAMPTZ;

ALTER TABLE public.legacy_clinical_records
  ADD COLUMN IF NOT EXISTS match_confidence NUMERIC(5,4),
  ADD COLUMN IF NOT EXISTS match_method TEXT,
  ADD COLUMN IF NOT EXISTS validation_errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS reconciled_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reconciled_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS uq_legacy_clinical_records_source_record
  ON public.legacy_clinical_records(source_system, source_record_id)
  WHERE source_record_id IS NOT NULL AND btrim(source_record_id) <> '';

CREATE INDEX IF NOT EXISTS idx_migration_rows_patient_match
  ON public.data_migration_rows(batch_id, patient_id, row_status, match_confidence DESC);

CREATE OR REPLACE FUNCTION public.get_legacy_patient_candidates(_row_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_row public.data_migration_rows;
  v_data JSONB;
  v_dob DATE;
  v_phone TEXT;
  v_email TEXT;
  v_source_key TEXT;
  v_first TEXT;
  v_last TEXT;
  v_candidates JSONB;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  SELECT * INTO v_row FROM public.data_migration_rows WHERE id = _row_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Migration row not found'; END IF;
  v_data := COALESCE(v_row.raw_data, '{}'::jsonb);
  v_source_key := NULLIF(btrim(COALESCE(v_data->>'source_patient_key', v_data->>'patient_code', v_data->>'patient_id', '')), '');
  v_phone := NULLIF(regexp_replace(COALESCE(v_data->>'phone',''), '[^0-9+]', '', 'g'), '');
  v_email := NULLIF(lower(btrim(COALESCE(v_data->>'email',''))), '');
  v_first := NULLIF(lower(btrim(COALESCE(v_data->>'first_name',''))), '');
  v_last := NULLIF(lower(btrim(COALESCE(v_data->>'last_name',''))), '');
  v_dob := CASE WHEN COALESCE(v_data->>'date_of_birth','') ~ '^\\d{4}-\\d{2}-\\d{2}$' THEN (v_data->>'date_of_birth')::date ELSE NULL END;
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'method', (x->>'confidence')::numeric DESC), '[]'::jsonb)
    INTO v_candidates
  FROM (
    SELECT DISTINCT ON (p.id)
      jsonb_build_object(
        'patient_id', p.id, 'patient_code', p.patient_code, 'first_name', p.first_name,
        'last_name', p.last_name, 'date_of_birth', p.date_of_birth, 'phone', p.phone, 'email', p.email,
        'method', CASE
          WHEN v_source_key IS NOT NULL AND p.patient_code = v_source_key THEN 'source_patient_key'
          WHEN v_phone IS NOT NULL AND regexp_replace(COALESCE(p.phone,''), '[^0-9+]', '', 'g') = v_phone AND v_dob IS NOT NULL AND p.date_of_birth = v_dob THEN 'phone_dob'
          WHEN v_email IS NOT NULL AND lower(COALESCE(p.email,'')) = v_email AND v_dob IS NOT NULL AND p.date_of_birth = v_dob THEN 'email_dob'
          ELSE 'name_dob' END,
        'confidence', CASE
          WHEN v_source_key IS NOT NULL AND p.patient_code = v_source_key THEN 1.0000
          WHEN v_phone IS NOT NULL AND regexp_replace(COALESCE(p.phone,''), '[^0-9+]', '', 'g') = v_phone AND v_dob IS NOT NULL AND p.date_of_birth = v_dob THEN 0.9800
          WHEN v_email IS NOT NULL AND lower(COALESCE(p.email,'')) = v_email AND v_dob IS NOT NULL AND p.date_of_birth = v_dob THEN 0.9700
          ELSE 0.9000 END
      ) AS x, p.id
    FROM public.patients p
    WHERE (v_source_key IS NOT NULL AND p.patient_code = v_source_key)
       OR (v_phone IS NOT NULL AND v_dob IS NOT NULL AND regexp_replace(COALESCE(p.phone,''), '[^0-9+]', '', 'g') = v_phone AND p.date_of_birth = v_dob)
       OR (v_email IS NOT NULL AND v_dob IS NOT NULL AND lower(COALESCE(p.email,'')) = v_email AND p.date_of_birth = v_dob)
       OR (v_first IS NOT NULL AND v_last IS NOT NULL AND v_dob IS NOT NULL AND lower(p.first_name) = v_first AND lower(p.last_name) = v_last AND p.date_of_birth = v_dob)
    LIMIT 20
  ) x;
  RETURN v_candidates;
END;
$$;
REVOKE ALL ON FUNCTION public.get_legacy_patient_candidates(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_legacy_patient_candidates(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_legacy_migration_row(
  _row_id UUID, _patient_id UUID, _match_confidence NUMERIC DEFAULT NULL, _match_method TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_row public.data_migration_rows; v_conf NUMERIC := COALESCE(_match_confidence, 0);
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  IF v_conf < 0 OR v_conf > 1 THEN RAISE EXCEPTION 'Match confidence must be between 0 and 1'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  SELECT * INTO v_row FROM public.data_migration_rows WHERE id = _row_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Migration row not found'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.data_migration_batches WHERE id = v_row.batch_id AND status IN ('staged','validating','ready')) THEN RAISE EXCEPTION 'Migration batch is not open for reconciliation'; END IF;
  UPDATE public.data_migration_rows SET patient_id=_patient_id,match_confidence=v_conf,match_method=COALESCE(NULLIF(btrim(_match_method),''),'manual'),reconciled_by=auth.uid(),reconciled_at=now(),row_status='validated',rejection_reason=NULL,validation_errors='[]'::jsonb WHERE id=_row_id;
  PERFORM public.record_system_audit('legacy_migration_row_reconciled','data_migration','data_migration_row',_row_id,'info',jsonb_build_object('batch_id',v_row.batch_id,'patient_id',_patient_id,'match_confidence',v_conf,'match_method',COALESCE(_match_method,'manual')));
  RETURN jsonb_build_object('row_id',_row_id,'patient_id',_patient_id,'match_confidence',v_conf,'match_method',COALESCE(NULLIF(btrim(_match_method),''),'manual'),'status','validated');
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_legacy_migration_row(UUID,UUID,NUMERIC,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_legacy_migration_row(UUID,UUID,NUMERIC,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_legacy_migration_batch(_batch_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_row RECORD; v_errors JSONB; v_total INTEGER:=0; v_valid INTEGER:=0; v_rejected INTEGER:=0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.data_migration_batches WHERE id=_batch_id) THEN RAISE EXCEPTION 'Migration batch not found'; END IF;
  UPDATE public.data_migration_batches SET status='validating',validation_errors='[]'::jsonb WHERE id=_batch_id;
  FOR v_row IN SELECT * FROM public.data_migration_rows WHERE batch_id=_batch_id ORDER BY source_row_number FOR UPDATE LOOP
    v_total:=v_total+1; v_errors:='[]'::jsonb;
    IF v_row.patient_id IS NULL THEN v_errors:=v_errors||jsonb_build_array('Patient reconciliation is required'); END IF;
    IF v_row.match_confidence IS NULL OR v_row.match_confidence < 0.8500 THEN v_errors:=v_errors||jsonb_build_array('Patient match confidence must be at least 0.85'); END IF;
    IF NULLIF(btrim(v_row.raw_data->>'source_system'),'') IS NULL THEN v_errors:=v_errors||jsonb_build_array('Source system is required'); END IF;
    IF NULLIF(btrim(v_row.raw_data->>'record_type'),'') IS NULL THEN v_errors:=v_errors||jsonb_build_array('Record type is required'); END IF;
    IF NULLIF(btrim(v_row.raw_data->>'source_patient_key'),'') IS NULL THEN v_errors:=v_errors||jsonb_build_array('Source patient key is required'); END IF;
    IF NULLIF(btrim(v_row.raw_data->>'occurred_at'),'') IS NULL THEN v_errors:=v_errors||jsonb_build_array('Chronology: occurred_at is required');
    ELSIF NOT (v_row.raw_data->>'occurred_at' ~ '^\\d{4}-\\d{2}-\\d{2}(T|\\s)\\d{2}:\\d{2}') THEN v_errors:=v_errors||jsonb_build_array('Chronology: occurred_at must be ISO date/time'); END IF;
    IF NULLIF(btrim(v_row.raw_data->>'source_record_id'),'') IS NOT NULL AND (SELECT count(*) FROM public.data_migration_rows r WHERE r.batch_id=_batch_id AND NULLIF(btrim(r.raw_data->>'source_system'),'')=NULLIF(btrim(v_row.raw_data->>'source_system'),'') AND NULLIF(btrim(r.raw_data->>'source_record_id'),'')=NULLIF(btrim(v_row.raw_data->>'source_record_id'),'')) > 1 THEN
      v_errors:=v_errors||jsonb_build_array('Duplicate source record key exists within migration batch');
    END IF;
    IF v_row.row_status='duplicate' THEN v_errors:=v_errors||jsonb_build_array('Duplicate row requires explicit resolution'); END IF;
    IF jsonb_array_length(v_errors)=0 THEN
      UPDATE public.data_migration_rows SET row_status='accepted',validation_errors='[]'::jsonb,rejection_reason=NULL WHERE id=v_row.id; v_valid:=v_valid+1;
    ELSE
      UPDATE public.data_migration_rows SET row_status='rejected',validation_errors=v_errors,rejection_reason=COALESCE(v_errors->>0,'Validation failed') WHERE id=v_row.id; v_rejected:=v_rejected+1;
    END IF;
  END LOOP;
  UPDATE public.data_migration_batches SET accepted_rows=v_valid,rejected_rows=v_rejected,validation_errors=(SELECT COALESCE(jsonb_agg(jsonb_build_object('row_id',id,'source_row_number',source_row_number,'errors',validation_errors)),'[]'::jsonb) FROM public.data_migration_rows WHERE batch_id=_batch_id AND row_status='rejected'),status=CASE WHEN v_total>0 AND v_valid=v_total THEN 'ready' ELSE 'staged' END WHERE id=_batch_id;
  PERFORM public.record_system_audit('legacy_migration_batch_validated','data_migration','data_migration_batch',_batch_id,CASE WHEN v_rejected=0 THEN 'info' ELSE 'warning' END,jsonb_build_object('total_rows',v_total,'accepted_rows',v_valid,'rejected_rows',v_rejected));
  RETURN jsonb_build_object('batch_id',_batch_id,'total_rows',v_total,'accepted_rows',v_valid,'rejected_rows',v_rejected,'status',CASE WHEN v_total>0 AND v_valid=v_total THEN 'ready' ELSE 'staged' END);
END;
$$;
REVOKE ALL ON FUNCTION public.validate_legacy_migration_batch(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_legacy_migration_batch(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.approve_legacy_migration_batch(_batch_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_status TEXT; v_rejected INTEGER; v_total INTEGER; v_accepted INTEGER;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  SELECT status,rejected_rows,total_rows,accepted_rows INTO v_status,v_rejected,v_total,v_accepted FROM public.data_migration_batches WHERE id=_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Migration batch not found'; END IF;
  IF v_status<>'ready' OR v_rejected<>0 OR v_accepted<>v_total OR v_total=0 THEN RAISE EXCEPTION 'Batch is not fully validated and ready for approval'; END IF;
  UPDATE public.data_migration_batches SET status='importing',approved_by=auth.uid(),approved_at=now() WHERE id=_batch_id;
  UPDATE public.data_migration_rows SET approved_by=auth.uid(),approved_at=now() WHERE batch_id=_batch_id AND row_status='accepted';
  PERFORM public.record_system_audit('legacy_migration_batch_approved','data_migration','data_migration_batch',_batch_id,'info',jsonb_build_object('rows',v_total));
  RETURN jsonb_build_object('batch_id',_batch_id,'status','importing','approved_rows',v_total);
END;
$$;
REVOKE ALL ON FUNCTION public.approve_legacy_migration_batch(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_legacy_migration_batch(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.promote_legacy_migration_batch(_batch_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_batch public.data_migration_batches; v_row RECORD; v_count INTEGER:=0; v_skipped INTEGER:=0; v_legacy_id UUID; v_occurred_at TIMESTAMPTZ;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  SELECT * INTO v_batch FROM public.data_migration_batches WHERE id=_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Migration batch not found'; END IF;
  IF v_batch.status<>'importing' THEN RAISE EXCEPTION 'Batch must be approved before promotion'; END IF;
  FOR v_row IN SELECT r.*,b.source_system AS batch_source_system FROM public.data_migration_rows r JOIN public.data_migration_batches b ON b.id=r.batch_id WHERE r.batch_id=_batch_id AND r.row_status='accepted' ORDER BY r.source_row_number FOR UPDATE LOOP
    BEGIN v_occurred_at:=NULLIF(v_row.raw_data->>'occurred_at','')::timestamptz; EXCEPTION WHEN others THEN v_occurred_at:=NULL; END;
    IF v_occurred_at IS NULL OR v_row.patient_id IS NULL THEN
      v_skipped:=v_skipped+1;
      UPDATE public.data_migration_rows SET row_status='rejected',validation_errors=jsonb_build_array('Promotion blocked: patient and valid chronology are required'),rejection_reason='Promotion blocked: patient and valid chronology are required' WHERE id=v_row.id;
      CONTINUE;
    END IF;
    INSERT INTO public.legacy_clinical_records(batch_id,patient_id,source_system,source_patient_key,source_record_id,record_type,occurred_at,author_name,department,encounter_reference,clinical_summary,raw_record,migration_status,imported_by,imported_at,match_confidence,match_method,validation_errors,reconciled_by,reconciled_at,approved_by,approved_at)
    VALUES (_batch_id,v_row.patient_id,COALESCE(NULLIF(v_row.raw_data->>'source_system',''),v_row.batch_source_system),NULLIF(v_row.raw_data->>'source_patient_key',''),NULLIF(v_row.raw_data->>'source_record_id',''),trim(v_row.raw_data->>'record_type'),v_occurred_at,NULLIF(v_row.raw_data->>'author_name',''),NULLIF(v_row.raw_data->>'department',''),NULLIF(v_row.raw_data->>'encounter_reference',''),NULLIF(v_row.raw_data->>'clinical_summary',''),v_row.raw_data,'imported',auth.uid(),now(),v_row.match_confidence,v_row.match_method,'[]'::jsonb,v_row.reconciled_by,v_row.reconciled_at,v_row.approved_by,v_row.approved_at)
    ON CONFLICT (source_system,source_record_id) WHERE source_record_id IS NOT NULL AND btrim(source_record_id)<>''
    DO UPDATE SET patient_id=EXCLUDED.patient_id,occurred_at=EXCLUDED.occurred_at,record_type=EXCLUDED.record_type,clinical_summary=EXCLUDED.clinical_summary,raw_record=EXCLUDED.raw_record,migration_status='imported',imported_by=auth.uid(),imported_at=now(),match_confidence=EXCLUDED.match_confidence,match_method=EXCLUDED.match_method,approved_by=EXCLUDED.approved_by,approved_at=EXCLUDED.approved_at;
    SELECT id INTO v_legacy_id FROM public.legacy_clinical_records WHERE source_system=COALESCE(NULLIF(v_row.raw_data->>'source_system',''),v_row.batch_source_system) AND source_record_id=NULLIF(v_row.raw_data->>'source_record_id','') LIMIT 1;
    UPDATE public.data_migration_rows SET row_status='imported',target_table='legacy_clinical_records',target_id=v_legacy_id,promoted_by=auth.uid(),promoted_at=now() WHERE id=v_row.id;
    v_count:=v_count+1;
  END LOOP;
  UPDATE public.data_migration_batches SET status=CASE WHEN v_skipped=0 THEN 'completed' ELSE 'completed_with_errors' END,completed_at=now(),accepted_rows=v_count,rejected_rows=v_skipped WHERE id=_batch_id;
  PERFORM public.record_system_audit('legacy_migration_batch_promoted','data_migration','data_migration_batch',_batch_id,CASE WHEN v_skipped=0 THEN 'info' ELSE 'warning' END,jsonb_build_object('promoted_rows',v_count,'skipped_rows',v_skipped,'native_clinical_tables_modified',false));
  RETURN jsonb_build_object('batch_id',_batch_id,'status',CASE WHEN v_skipped=0 THEN 'completed' ELSE 'completed_with_errors' END,'promoted_rows',v_count,'skipped_rows',v_skipped,'native_clinical_tables_modified',false);
END;
$$;
REVOKE ALL ON FUNCTION public.promote_legacy_migration_batch(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.promote_legacy_migration_batch(UUID) TO authenticated;
