select ok(to_regprocedure('public.get_ai_clinical_context(uuid)') is not null,'AI clinical context RPC exists');
select ok(not has_function_privilege('anon','public.get_ai_clinical_context(uuid)','EXECUTE'),'anon cannot execute AI clinical context RPC');
select ok(has_function_privilege('authenticated','public.get_ai_clinical_context(uuid)','EXECUTE'),'authenticated can invoke guarded AI clinical context RPC');
select ok(position('national_id' in pg_get_functiondef('public.get_ai_clinical_context(uuid)'::regprocedure)) = 0,'AI context function does not expose national_id directly');
select ok(position('get_patient_admission_history' in pg_get_functiondef('public.get_ai_clinical_context(uuid)'::regprocedure)) > 0,'AI context uses scoped admission history');
