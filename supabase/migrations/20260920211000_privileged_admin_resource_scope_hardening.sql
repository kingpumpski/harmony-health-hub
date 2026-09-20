-- Harden privileged data-migration staging and facility report seeding.
CREATE OR REPLACE FUNCTION public.stage_data_migration_rows(_batch_id uuid, _rows jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_count integer:=0; v_item jsonb; v_row integer:=0; v_batch public.data_migration_batches%ROWTYPE; v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL OR NOT public.has_role(v_user,'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
 SELECT * INTO v_batch FROM public.data_migration_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Migration batch not found'; END IF;
 IF v_batch.created_by IS DISTINCT FROM v_user THEN RAISE EXCEPTION 'Only the batch creator may stage rows'; END IF;
 IF COALESCE(v_batch.status,'') NOT IN ('created','staged') THEN RAISE EXCEPTION 'Migration batch is not open for staging'; END IF;
 IF jsonb_typeof(COALESCE(_rows,'[]'::jsonb)) <> 'array' THEN RAISE EXCEPTION 'Rows payload must be a JSON array'; END IF;
 IF jsonb_array_length(COALESCE(_rows,'[]'::jsonb)) > 10000 THEN RAISE EXCEPTION 'A maximum of 10000 rows may be staged per request'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(_rows,'[]'::jsonb)) LOOP
   v_row:=v_row+1;
   INSERT INTO public.data_migration_rows(batch_id,source_row_number,source_key,raw_data)
   VALUES(_batch_id,v_row,COALESCE(v_item->>'source_key',v_item->>'patient_code',v_item->>'id'),v_item)
   ON CONFLICT(batch_id,source_row_number) DO UPDATE SET raw_data=EXCLUDED.raw_data,row_status='staged',rejection_reason=NULL,normalized_data=NULL,validation_errors=NULL,target_id=NULL;
   v_count:=v_count+1;
 END LOOP;
 UPDATE public.data_migration_batches SET staged_rows=v_count,status='staged',validation_errors=NULL WHERE id=_batch_id;
 RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.seed_facility_reports(_facility_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL OR NOT public.has_role(v_user,'admin') THEN RAISE EXCEPTION 'Only administrators may seed facility reports'; END IF;
 IF _facility_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.healthcare_facilities hf WHERE hf.id=_facility_id) THEN RAISE EXCEPTION 'Facility not found'; END IF;
 IF NOT public.has_facility_access(v_user,_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;
 INSERT INTO public.facility_report_config(facility_id,report_id,is_enabled,submission_deadline_day)
 SELECT _facility_id,id,TRUE,submission_deadline_day FROM public.report_definitions WHERE is_active
 ON CONFLICT(facility_id,report_id) DO NOTHING;
END; $$;
REVOKE ALL ON FUNCTION public.stage_data_migration_rows(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.stage_data_migration_rows(uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.seed_facility_reports(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.seed_facility_reports(uuid) TO authenticated;