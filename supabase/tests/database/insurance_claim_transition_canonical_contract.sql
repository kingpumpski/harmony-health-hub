begin;

select plan(8);

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='transition_insurance_claim'
      and pg_get_function_identity_arguments(p.oid) in (
        'uuid, _status text, _amount_approved numeric, _amount_paid numeric, _rejection_reason text, _notes text, _to_status text',
        'uuid, _to_status text, _notes text'
      )
  ),
  'legacy insurance claim transition overloads are removed'
);

select ok(
  exists (
    select 1 from pg_proc p
    where p.oid='public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)'::regprocedure
      and p.prosecdef
      and p.proconfig @> array['search_path=pg_catalog, public']
  ),
  'canonical claim transition remains SECURITY DEFINER with a pinned search_path'
);

select ok(
  exists (
    select 1 from pg_proc p
    where p.oid='public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)'::regprocedure
      and p.prosecdef
      and p.proconfig @> array['search_path=pg_catalog, public']
  ),
  'claim financial mutation remains SECURITY DEFINER with a pinned search_path'
);

select ok(
  has_function_privilege('authenticated','public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)','EXECUTE')
  and not has_function_privilege('anon','public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)','EXECUTE')
  and not exists (
    select 1
    from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid='public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)'::regprocedure
      and a.grantee=0
      and a.privilege_type='EXECUTE'
  ),
  'canonical claim transition is executable by authenticated only, not anon or PUBLIC'
);

select ok(
  has_function_privilege('authenticated','public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)','EXECUTE')
  and not has_function_privilege('anon','public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)','EXECUTE')
  and not exists (
    select 1
    from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where p.oid='public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)'::regprocedure
      and a.grantee=0
      and a.privilege_type='EXECUTE'
  ),
  'claim financial mutation is executable by authenticated only, not anon or PUBLIC'
);

select ok(
  pg_get_functiondef('public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)'::regprocedure)
    ilike '%assert_patient_facility_context(c.patient_id)%'
  and pg_get_functiondef('public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)'::regprocedure)
    ilike '%c.facility_id is distinct from%',
  'claim transition revalidates caller patient context and claim-to-patient facility lineage'
);

select ok(
  pg_get_functiondef('public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)'::regprocedure)
    ilike '%i.patient_id=c.patient_id%'
  and pg_get_functiondef('public.transition_insurance_claim_canonical(uuid,text,numeric,numeric,text,text)'::regprocedure)
    ilike '%i.facility_id=c.facility_id%',
  'claim transition rejects invoices whose patient or facility differs from the claim'
);

select ok(
  pg_get_functiondef('public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)'::regprocedure)
    ilike '%assert_patient_facility_context(c.patient_id)%'
  and pg_get_functiondef('public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)'::regprocedure)
    ilike '%c.facility_id is distinct from%'
  and pg_get_functiondef('public.update_insurance_claim_financials(uuid,numeric,numeric,text,text)'::regprocedure)
    ilike '%i.facility_id=c.facility_id%',
  'claim financial edits enforce patient, claim, and invoice facility lineage'
);

select * from finish();
rollback;
