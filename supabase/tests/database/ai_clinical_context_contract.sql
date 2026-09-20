select ok(to_regprocedure('public.get_ai_clinical_context(uuid)') is not null,'AI clinical context RPC exists');
select ok(not has_function_privilege('anon','public.get_ai_clinical_context(uuid)','EXECUTE'),'anon cannot execute AI clinical context RPC');
select ok(has_function_privilege('authenticated','public.get_ai_clinical_context(uuid)','EXECUTE'),'authenticated can invoke guarded AI clinical context RPC');
