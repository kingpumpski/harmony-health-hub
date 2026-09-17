begin;

select plan(20);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_roles'::regclass),
  'user_roles has RLS enabled'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_roles'
      and policyname = 'user_roles_select_own'
      and qual is not null
      and qual ilike '%auth.uid%'
  ),
  'user_roles read policy is scoped to the current user'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'facility_memberships'
      and policyname = 'memberships_read'
      and qual is not null
      and qual ilike '%auth.uid%'
  ),
  'facility membership reads are scoped to the current user or administrator'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.notify_due_medications()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.lock_overdue_medication_slots()',
    'EXECUTE'
  ),
  'internal medication maintenance functions are not callable by authenticated clients'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'patients'
      and policyname = 'authorized users read patients'
      and qual is not null
      and qual not in ('true', '(true)')
  ),
  'patient reads are governed by an authorization predicate'
);

select ok(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'grant_service_order_override',
        'release_service_order',
        'cancel_service_order',
        'mark_service_order_in_progress',
        'complete_service_order'
      )
      and p.prosecdef
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) = 5,
  'service-order lifecycle RPCs are security-definer and authenticated-only'
);

select ok(
  has_function_privilege('authenticated', 'public.release_service_order(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.release_service_order(uuid,text)', 'EXECUTE')
  and (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'release_service_order'
      and pg_get_function_identity_arguments(p.oid) = 'uuid, _reason text'
  ) ilike '%has_role(auth.uid(),''front_desk'')%',
  'payment release is authenticated-only and permits the front-desk payment workflow'
);

select ok(
  (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'grant_service_order_override'
      and pg_get_function_identity_arguments(p.oid) = 'uuid, _reason text'
  ) ilike '%status <> ''pending_payment_approval''%',
  'billing overrides are restricted to orders awaiting payment approval'
);

select ok(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'create_lab_order_with_payment_gate',
        'collect_lab_sample',
        'enter_lab_result',
        'approve_lab_result'
      )
      and p.prosecdef
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) = 4,
  'laboratory workflow RPCs are security-definer and authenticated-only'
);

select ok(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'find_pharmacy_alternatives',
        'prepare_pharmacy_dispensing',
        'confirm_pharmacy_dispense',
        'create_pharmacy_pos_sale',
        'confirm_pharmacy_pos_sale',
        'create_pharmacy_inventory_item'
      )
      and p.prosecdef
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) = 6,
  'pharmacy workflow RPCs are security-definer and authenticated-only'
);

select ok(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'create_insurance_claim_draft',
        'transition_insurance_claim',
        'update_insurance_claim_financials'
      )
      and p.prosecdef
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) = 3,
  'insurance claim mutation RPCs are security-definer and authenticated-only'
);

select ok(
  has_function_privilege('authenticated', 'public.pay_selected_invoice_items(uuid,uuid[],text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.pay_selected_invoice_items(uuid,uuid[],text,text)', 'EXECUTE'),
  'selected-invoice payment collection is authenticated-only'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'insurance_claims'
      and policyname = 'staff read claims'
      and qual is not null
      and qual ilike '%has_role%'
      and qual not in ('true', '(true)')
  ),
  'insurance claim reads are role-scoped rather than broadly exposed'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'payments'
      and policyname = 'staff read payments'
      and qual is not null
      and qual ilike '%has_role%'
      and qual not in ('true', '(true)')
  ),
  'payment reads are role-scoped rather than broadly exposed'
);

select ok(
  has_function_privilege('authenticated', 'public.set_facility_routing_mode(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.set_facility_routing_mode(text)', 'EXECUTE')
  and (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_facility_routing_mode'
      and pg_get_function_identity_arguments(p.oid) = '_mode text'
  ) ilike '%has_role(auth.uid(),''admin'')%'
  and (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_facility_routing_mode'
      and pg_get_function_identity_arguments(p.oid) = '_mode text'
  ) ilike '%Administrator role required%',
  'facility routing mode is authenticated-only and administrator-gated'
);

select ok(
  has_function_privilege('authenticated', 'public.recover_stale_report_run(uuid,integer)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.recover_stale_report_run(uuid,integer)', 'EXECUTE')
  and (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'recover_stale_report_run'
      and pg_get_function_identity_arguments(p.oid) = '_run_id uuid, _stale_after_minutes integer'
  ) ilike '%has_facility_access(v_user,v_run.facility_id)%',
  'report recovery is authenticated-only and facility-scoped'
);

select ok(
  (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'pay_selected_invoice_items'
      and pg_get_function_identity_arguments(p.oid) = '_invoice_id uuid, _item_ids uuid[], _method text, _reference text'
  ) ilike '%idempotent_replay%'
  and (
    select pg_get_functiondef(p.oid)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'pay_selected_invoice_items'
      and pg_get_function_identity_arguments(p.oid) = '_invoice_id uuid, _item_ids uuid[], _method text, _reference text'
  ) ilike '%lower(trim(reference)) = lower(normalized_reference)%',
  'selected-invoice payment rejects duplicate references through an idempotent replay boundary'
);

select ok(
  not has_function_privilege('public', 'public.audit_patient_change()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.audit_patient_change()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.audit_patient_change()', 'EXECUTE')
  and not has_function_privilege('public', 'public.validate_service_order_encounter()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.validate_service_order_encounter()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.validate_service_order_encounter()', 'EXECUTE'),
  'trigger-only SECURITY DEFINER helpers are outside the client execution surface'
);

select ok(
  not has_function_privilege('public', 'public.notify_due_medications()', 'EXECUTE')
  and not has_function_privilege('public', 'public.lock_overdue_medication_slots()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.notify_due_medications()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.lock_overdue_medication_slots()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.notify_due_medications()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.lock_overdue_medication_slots()', 'EXECUTE'),
  'scheduler-only medication maintenance helpers are outside the client execution surface'
);

select ok(
  not has_function_privilege('public', 'public.has_role(uuid,public.app_role)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.has_role(uuid,public.app_role)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.has_role(uuid,public.app_role)', 'EXECUTE')
  and not has_function_privilege('public', 'public.has_facility_access(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.has_facility_access(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.has_facility_access(uuid,uuid)', 'EXECUTE'),
  'arbitrary-user authorization helper probes are outside the client execution surface'
);

select ok(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'grant_service_order_override',
        'release_service_order',
        'cancel_service_order',
        'mark_service_order_in_progress',
        'complete_service_order',
        'create_lab_order_with_payment_gate',
        'collect_lab_sample',
        'enter_lab_result',
        'approve_lab_result'
      )
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not has_function_privilege('anon', p.oid, 'EXECUTE')
  ) = 9,
  'classified application SECURITY DEFINER workflow RPCs remain authenticated-only'
);

select * from finish();
rollback;
