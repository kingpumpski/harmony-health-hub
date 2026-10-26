-- Forward-compatible repair for installations where the earlier RLS migration
-- was already recorded or manually reconciled without this required table.
-- The historical creation is also restored in 20260910215228 for clean replay.
create table if not exists public.ai_diagnosis_suggestions (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid references public.encounters(id),
  suggested_icd text references public.icd_codes(code),
  reasoning text,
  model_version text,
  accepted boolean default false,
  created_at timestamptz default now()
);

alter table public.ai_diagnosis_suggestions enable row level security;
grant select, insert, update, delete on public.ai_diagnosis_suggestions to authenticated;
grant all on public.ai_diagnosis_suggestions to service_role;

drop policy if exists "clinical staff manage ai diagnosis suggestions" on public.ai_diagnosis_suggestions;
create policy "clinical staff manage ai diagnosis suggestions"
  on public.ai_diagnosis_suggestions for all to authenticated
  using (public.is_clinical_staff(auth.uid()))
  with check (public.is_clinical_staff(auth.uid()));

