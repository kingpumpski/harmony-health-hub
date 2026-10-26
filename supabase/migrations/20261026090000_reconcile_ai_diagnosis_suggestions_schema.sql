-- Forward-compatible repair for installations where earlier prerequisite
-- schemas were recorded or manually reconciled without these required tables.
-- Matching CREATE IF NOT EXISTS definitions also live before first use in
-- 20260910215228 so a clean replay succeeds deterministically.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  action text,
  table_name text,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz default now()
);

create table if not exists public.sync_queue (
  id uuid primary key default gen_random_uuid(),
  payload jsonb,
  synced boolean default false,
  table_name text
);

create table if not exists public.lab_tests (
  id uuid primary key default gen_random_uuid(),
  loinc_code text,
  normal_range text,
  specimen text,
  test_name text,
  created_at timestamptz default now()
);

create table if not exists public.ai_symptom_icd_map (
  id uuid primary key default gen_random_uuid(),
  confidence numeric,
  created_at timestamptz default now(),
  icd_code text references public.icd_codes(code),
  symptom text not null
);

create table if not exists public.ai_diagnosis_suggestions (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid references public.encounters(id),
  suggested_icd text references public.icd_codes(code),
  reasoning text,
  model_version text,
  accepted boolean default false,
  created_at timestamptz default now()
);

-- Reassert least-privilege grants and RLS for every restored relation.
alter table public.audit_logs enable row level security;
grant select on public.audit_logs to authenticated;
grant all on public.audit_logs to service_role;
drop policy if exists "admins read audit logs" on public.audit_logs;
create policy "admins read audit logs" on public.audit_logs
  for select to authenticated using (public.has_role(auth.uid(), 'admin'));

alter table public.sync_queue enable row level security;
grant all on public.sync_queue to service_role;
grant select on public.sync_queue to authenticated;
drop policy if exists "admins read sync queue" on public.sync_queue;
create policy "admins read sync queue" on public.sync_queue
  for select to authenticated using (public.has_role(auth.uid(), 'admin'));

alter table public.lab_tests enable row level security;
grant select on public.lab_tests to authenticated;
grant all on public.lab_tests to service_role;
drop policy if exists "staff read lab tests" on public.lab_tests;
create policy "staff read lab tests" on public.lab_tests
  for select to authenticated using (public.is_clinical_staff(auth.uid()));
drop policy if exists "admins write lab tests" on public.lab_tests;
create policy "admins write lab tests" on public.lab_tests
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

alter table public.ai_symptom_icd_map enable row level security;
grant select on public.ai_symptom_icd_map to authenticated;
grant all on public.ai_symptom_icd_map to service_role;
drop policy if exists "staff read symptom map" on public.ai_symptom_icd_map;
create policy "staff read symptom map" on public.ai_symptom_icd_map
  for select to authenticated using (public.is_clinical_staff(auth.uid()));
drop policy if exists "admins write symptom map" on public.ai_symptom_icd_map;
create policy "admins write symptom map" on public.ai_symptom_icd_map
  for all to authenticated
  using (public.has_role(auth.uid(), 'admin'))
  with check (public.has_role(auth.uid(), 'admin'));

alter table public.ai_diagnosis_suggestions enable row level security;
grant select, insert, update, delete on public.ai_diagnosis_suggestions to authenticated;
grant all on public.ai_diagnosis_suggestions to service_role;
drop policy if exists "clinical staff manage ai diagnosis suggestions" on public.ai_diagnosis_suggestions;
create policy "clinical staff manage ai diagnosis suggestions"
  on public.ai_diagnosis_suggestions for all to authenticated
  using (public.is_clinical_staff(auth.uid()))
  with check (public.is_clinical_staff(auth.uid()));


-- Reassert the execution boundary after historical hardening migrations:
-- the low-level helper stays internal, while the one-argument wrapper must be
-- executable by authenticated users because RLS policy expressions call it.
revoke execute on function public.has_facility_access(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.current_user_has_facility_access(uuid) from public, anon;
grant execute on function public.current_user_has_facility_access(uuid) to authenticated;

-- Reassert hardened execution context for clinical order creation on databases
-- where the historical function definitions were already applied.
alter function public.create_imaging_order_with_payment_gate(uuid, uuid, text, text, text, text, text, numeric)
  set search_path = '';
alter function public.create_lab_order_with_payment_gate(uuid, text, text, text, text, numeric)
  set search_path = '';

-- Canonical billing aliases referenced by reconciliation workflows.
-- Keep prices at zero until the facility imports/configures its approved tariff schedule.
INSERT INTO public.service_tariffs
  (service_code, service_name, category, department, unit, amount, active, currency, metadata)
VALUES
  ('WARD-ACCOM','Accommodation / detention','ward','ward','day',0,true,'GHS',
   jsonb_build_object('canonical_alias_for','WARD-ACCOM','requires_facility_tariff_configuration',true)),
  ('MEAL','Patient feeding','feeding','feeding','meal',0,true,'GHS',
   jsonb_build_object('canonical_alias_for','MEAL','requires_facility_tariff_configuration',true)),
  ('PROCEDURE-GENERIC','Other medical service / procedure','procedure','procedure','service',0,true,'GHS',
   jsonb_build_object('canonical_alias_for','PROCEDURE','requires_facility_tariff_configuration',true))
ON CONFLICT (service_code) DO UPDATE
SET service_name=EXCLUDED.service_name,
    category=EXCLUDED.category,
    department=EXCLUDED.department,
    unit=EXCLUDED.unit,
    active=true,
    metadata=EXCLUDED.metadata,
    updated_at=now();
-- Reassert the caller-scoped multi-role helper for installations that have
-- already recorded the historical role bootstrap migration.
CREATE OR REPLACE FUNCTION public.has_any_role(_roles public.app_role[])
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = ''
AS $has_any_role$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid()
      AND role = ANY(_roles)
  );
$has_any_role$;
REVOKE EXECUTE ON FUNCTION public.has_any_role(public.app_role[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_any_role(public.app_role[]) TO authenticated;
