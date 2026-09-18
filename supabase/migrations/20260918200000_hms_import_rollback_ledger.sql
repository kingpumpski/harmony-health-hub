CREATE TABLE IF NOT EXISTS public.hms_import_commit_ledger(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), batch_id uuid NOT NULL REFERENCES public.hms_import_batches(id) ON DELETE CASCADE,
 target_table text NOT NULL CHECK(target_table='patients'), target_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(batch_id,target_table,target_id)
);
ALTER TABLE public.hms_import_commit_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY hms_import_commit_ledger_admin ON public.hms_import_commit_ledger FOR ALL TO authenticated
 USING(public.has_role((SELECT auth.uid()),'admin'::public.app_role))
 WITH CHECK(public.has_role((SELECT auth.uid()),'admin'::public.app_role));
CREATE POLICY hms_import_commit_ledger_service ON public.hms_import_commit_ledger FOR ALL TO service_role USING(true) WITH CHECK(true);

CREATE OR REPLACE FUNCTION public.commit_hms_import_batch(_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; t hms_import_templates%ROWTYPE; s record; inserted int:=0; allowed jsonb; new_id uuid;
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
     'chronic_conditions',s.normalized_payload->'chronic_conditions','insurance_provider',s.normalized_payload->'insurance_provider',
     'insurance_number',s.normalized_payload->'insurance_number','emergency_contact_name',s.normalized_payload->'emergency_contact_name',
     'emergency_contact_phone',s.normalized_payload->'emergency_contact_phone');
   INSERT INTO public.patients SELECT (jsonb_populate_record(NULL::public.patients,allowed)).* RETURNING id INTO new_id;
   INSERT INTO public.hms_import_commit_ledger(batch_id,target_table,target_id) VALUES(_batch_id,'patients',new_id);
   inserted:=inserted+1;
 END LOOP;
 UPDATE public.hms_import_batches SET status='committed',committed_by=auth.uid(),committed_at=now(),accepted_count=inserted WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'committed',auth.uid(),jsonb_build_object('inserted',inserted,'reversible_until',now()+interval '30 days'));
 RETURN jsonb_build_object('batch_id',_batch_id,'status','committed','inserted',inserted);
EXCEPTION WHEN OTHERS THEN
 UPDATE public.hms_import_batches SET status='commit_failed' WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'commit_failed',auth.uid(),jsonb_build_object('error',SQLERRM));
 RAISE;
END $$;
REVOKE ALL ON FUNCTION public.commit_hms_import_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.commit_hms_import_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rollback_hms_import_batch(_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; l record; removed int:=0;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Import rollback authorization required'; END IF;
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND OR b.status<>'committed' OR b.committed_at < now()-interval '30 days' THEN RAISE EXCEPTION 'Batch is not eligible for rollback'; END IF;
 FOR l IN SELECT target_id FROM public.hms_import_commit_ledger WHERE batch_id=_batch_id ORDER BY created_at DESC FOR UPDATE LOOP
   DELETE FROM public.patients WHERE id=l.target_id;
   IF FOUND THEN removed:=removed+1; END IF;
 END LOOP;
 UPDATE public.hms_import_batches SET status='rolled_back',rollback_at=now() WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'rolled_back',auth.uid(),jsonb_build_object('removed',removed));
 RETURN jsonb_build_object('batch_id',_batch_id,'status','rolled_back','removed',removed);
END $$;
REVOKE ALL ON FUNCTION public.rollback_hms_import_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rollback_hms_import_batch(uuid) TO authenticated;
