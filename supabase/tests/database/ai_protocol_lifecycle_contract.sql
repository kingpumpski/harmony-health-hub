select ok(to_regprocedure('public.create_ai_protocol_draft(text,text,integer,text)') is not null,'AI protocol draft RPC exists');
select ok(to_regprocedure('public.transition_ai_protocol(uuid,text)') is not null,'AI protocol transition RPC exists');
select ok(not has_function_privilege('anon','public.create_ai_protocol_draft(text,text,integer,text)','EXECUTE'),'anon cannot create protocol drafts');
select ok(not has_function_privilege('anon','public.transition_ai_protocol(uuid,text)','EXECUTE'),'anon cannot transition protocols');
select ok(not has_table_privilege('authenticated','public.ai_protocols','INSERT'),'authenticated cannot directly insert protocols');
select ok(not has_table_privilege('authenticated','public.ai_protocols','UPDATE'),'authenticated cannot directly update protocols');
select ok(not has_table_privilege('authenticated','public.ai_protocols','DELETE'),'authenticated cannot directly delete protocols');
select ok(has_function_privilege('authenticated','public.create_ai_protocol_draft(text,text,integer,text)','EXECUTE'),'authenticated can invoke guarded draft creation');
select ok(has_function_privilege('authenticated','public.transition_ai_protocol(uuid,text)','EXECUTE'),'authenticated can invoke guarded lifecycle transition');
