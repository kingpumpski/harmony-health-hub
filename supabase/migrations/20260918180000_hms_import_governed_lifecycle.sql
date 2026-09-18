-- Governed import lifecycle: staging -> validation -> approval -> atomic commit/rollback.
CREATE OR REPLACE FUNCTION public.create_hms_import_batch(_template_code text,_source_filename text,_rows jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_template hms_import_templates%ROWTYPE; v_batch uuid; v_row jsonb; v_no int:=0;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Import administrator authorization required'; END IF;
 SELECT * INTO v_template FROM public.hms_import_templates WHERE code=_template_code AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active import template not found'; END IF;
 IF jsonb_typeof(_rows) <> 'array' OR jsonb_array_length(_rows)=0 THEN RAISE EXCEPTION 'Import rows must be a non-empty JSON array'; END IF;
 INSERT INTO public.hms_import_batches(template_id,template_version,source_filename,row_count,created_by)
 VALUES(v_template.id,v_template.current_version,_source_filename,jsonb_array_length(_rows),auth.uid()) RETURNING id INTO v_batch;
 FOR v_row IN SELECT value FROM jsonb_array_elements(_rows) LOOP
   v_no:=v_no+1;
   INSERT INTO public.hms_import_staging(batch_id,row_number,payload) VALUES(v_batch,v_no,v_row);
 END LOOP;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(v_batch,'created',auth.uid(),jsonb_build_object('rows',jsonb_array_length(_rows)));
 RETURN v_batch;
END $$;
REVOKE ALL ON FUNCTION public.create_hms_import_batch(text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_hms_import_batch(text,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_hms_import_batch(_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; s record; err_count int:=0; quarantine_count int:=0; valid_count int:=0; p jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Import administrator authorization required'; END IF;
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Import batch not found'; END IF;
 IF b.status NOT IN ('uploaded','validating','validated','quarantined') THEN RAISE EXCEPTION 'Batch cannot be validated in status %',b.status; END IF;
 UPDATE public.hms_import_batches SET status='validating' WHERE id=_batch_id;
 DELETE FROM public.hms_import_errors WHERE batch_id=_batch_id;
 UPDATE public.hms_import_staging SET validation_status='pending',validation_errors='[]'::jsonb WHERE batch_id=_batch_id;
 FOR s IN SELECT * FROM public.hms_import_staging WHERE batch_id=_batch_id ORDER BY row_number FOR UPDATE LOOP
   p:=s.payload;
   IF jsonb_typeof(p)<>'object' THEN
     UPDATE public.hms_import_staging SET validation_status='reject',validation_errors='["ROW_NOT_OBJECT"]'::jsonb WHERE id=s.id;
     INSERT INTO public.hms_import_errors(batch_id,staging_id,severity,code,message) VALUES(_batch_id,s.id,'REJECT','ROW_NOT_OBJECT','Each imported row must be an object'); err_count:=err_count+1; CONTINUE;
   END IF;
   IF (SELECT module_code FROM public.hms_import_templates t WHERE t.id=b.template_id)='M1' AND (coalesce(nullif(trim(p->>'first_name'),''),'')='' OR coalesce(nullif(trim(p->>'last_name'),''),'')='') THEN
     UPDATE public.hms_import_staging SET validation_status='quarantine',validation_errors='["PATIENT_NAME_REQUIRED"]'::jsonb WHERE id=s.id;
     INSERT INTO public.hms_import_quarantine(staging_id) VALUES(s.id);
     INSERT INTO public.hms_import_errors(batch_id,staging_id,severity,code,message) VALUES(_batch_id,s.id,'QUARANTINE','PATIENT_NAME_REQUIRED','Patient first_name and last_name are required'); quarantine_count:=quarantine_count+1; CONTINUE;
   END IF;
   UPDATE public.hms_import_staging SET validation_status='pass',normalized_payload=p WHERE id=s.id; valid_count:=valid_count+1;
 END LOOP;
 UPDATE public.hms_import_batches SET status=CASE WHEN err_count>0 AND valid_count=0 THEN 'quarantined' WHEN err_count>0 OR quarantine_count>0 THEN 'quarantined' ELSE 'validated' END,accepted_count=valid_count,rejected_count=err_count,quarantine_count=quarantine_count WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'validated',auth.uid(),jsonb_build_object('valid',valid_count,'rejected',err_count,'quarantine',quarantine_count));
 RETURN jsonb_build_object('batch_id',_batch_id,'valid',valid_count,'rejected',err_count,'quarantine',quarantine_count);
END $$;
REVOKE ALL ON FUNCTION public.validate_hms_import_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_hms_import_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.approve_hms_import_batch(_batch_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Import approval authorization required'; END IF;
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND OR b.status<>'validated' THEN RAISE EXCEPTION 'Only a fully validated batch may be approved'; END IF;
 UPDATE public.hms_import_batches SET status='approved',approved_by=auth.uid() WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id) VALUES(_batch_id,'approved',auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.approve_hms_import_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_hms_import_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.commit_hms_import_batch(_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; t hms_import_templates%ROWTYPE; s record; inserted int:=0; allowed jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Import commit authorization required'; END IF;
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND OR b.status<>'approved' THEN RAISE EXCEPTION 'Only approved batches may be committed'; END IF;
 SELECT * INTO t FROM public.hms_import_templates WHERE id=b.template_id;
 IF t.module_code<>'M1' OR t.entity_name<>'patients' THEN RAISE EXCEPTION 'No governed commit adapter exists for template %',t.code; END IF;
 IF EXISTS(SELECT 1 FROM public.hms_import_staging WHERE batch_id=_batch_id AND validation_status<>'pass') THEN RAISE EXCEPTION 'Batch contains non-pass rows'; END IF;
 FOR s IN SELECT normalized_payload FROM public.hms_import_staging WHERE batch_id=_batch_id ORDER BY row_number LOOP
   allowed:=jsonb_build_object(
     'first_name',s.normalized_payload->'first_name','last_name',s.normalized_payload->'last_name',
     'date_of_birth',s.normalized_payload->'date_of_birth','gender',s.normalized_payload->'gender',
     'phone',s.normalized_payload->'phone','email',s.normalized_payload->'email',
     'address',s.normalized_payload->'address','city',s.normalized_payload->'city',
     'ghana_card_number',s.normalized_payload->'ghana_card_number','blood_group',s.normalized_payload->'blood_group',
     'genotype',s.normalized_payload->'genotype','allergies',s.normalized_payload->'allergies',
     'chronic_conditions',s.normalized_payload->'chronic_conditions',
     'insurance_provider',s.normalized_payload->'insurance_provider','insurance_number',s.normalized_payload->'insurance_number',
     'emergency_contact_name',s.normalized_payload->'emergency_contact_name','emergency_contact_phone',s.normalized_payload->'emergency_contact_phone');
   INSERT INTO public.patients SELECT (jsonb_populate_record(NULL::public.patients,allowed)).*;
   inserted:=inserted+1;
 END LOOP;
 UPDATE public.hms_import_batches SET status='committed',committed_by=auth.uid(),committed_at=now(),accepted_count=inserted WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'committed',auth.uid(),jsonb_build_object('inserted',inserted));
 RETURN jsonb_build_object('batch_id',_batch_id,'status','committed','inserted',inserted);
EXCEPTION WHEN OTHERS THEN
 UPDATE public.hms_import_batches SET status='commit_failed' WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'commit_failed',auth.uid(),jsonb_build_object('error',SQLERRM));
 RAISE;
END $$;
REVOKE ALL ON FUNCTION public.commit_hms_import_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.commit_hms_import_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rollback_hms_import_batch(_batch_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Import rollback authorization required'; END IF;
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND OR b.status<>'committed' OR b.committed_at < now()-interval '30 days' THEN RAISE EXCEPTION 'Batch is not eligible for rollback'; END IF;
 RAISE EXCEPTION 'Rollback requires an entity-specific compensating adapter; direct deletion is prohibited';
END $$;
REVOKE ALL ON FUNCTION public.rollback_hms_import_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rollback_hms_import_batch(uuid) TO authenticated;

REVOKE ALL ON TABLE public.hms_import_templates,public.hms_import_template_versions,public.hms_import_batches,public.hms_import_staging,public.hms_import_errors,public.hms_import_quarantine,public.hms_import_mappings,public.hms_import_audit FROM authenticated;
GRANT SELECT ON public.hms_import_templates,public.hms_import_template_versions,public.hms_import_batches,public.hms_import_staging,public.hms_import_errors,public.hms_import_quarantine,public.hms_import_mappings,public.hms_import_audit TO authenticated;
