-- Fix prepare_patient_billable_items output-column/column-name ambiguity.
-- The function returns an output column named amount, so unqualified
-- service_tariffs.amount references can resolve ambiguously inside PL/pgSQL.
do $migration$
declare
  v_definition text;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_proc p
  where p.oid = 'public.prepare_patient_billable_items(uuid,timestamptz,timestamptz)'::regprocedure;

  if v_definition is null then
    raise exception 'prepare_patient_billable_items function not found';
  end if;

  v_definition := replace(
    v_definition,
    'SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code=',
    'SELECT st.amount INTO tariff FROM public.service_tariffs st WHERE st.service_code='
  );

  execute v_definition;
end;
$migration$;