select ok(to_regprocedure('public.get_ai_case_memory_for_diagnosis(text,integer)') is not null,'AI case-memory scoped RPC exists');
select ok(to_regprocedure('public.get_ai_report_requests(uuid,integer)') is not null,'AI report scoped RPC exists');
select ok(not has_function_privilege('anon','public.get_ai_case_memory_for_diagnosis(text,integer)','EXECUTE'),'anon cannot execute case-memory RPC');
select ok(not has_function_privilege('anon','public.get_ai_report_requests(uuid,integer)','EXECUTE'),'anon cannot execute report RPC');
select ok(has_function_privilege('authenticated','public.get_ai_case_memory_for_diagnosis(text,integer)','EXECUTE'),'authenticated can execute case-memory RPC');
select ok(has_function_privilege('authenticated','public.get_ai_report_requests(uuid,integer)','EXECUTE'),'authenticated can execute report RPC');
