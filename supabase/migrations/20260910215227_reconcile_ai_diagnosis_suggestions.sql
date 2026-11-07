-- Restore AI diagnosis suggestions before RLS hardening and facility lineage.
create table if not exists public.ai_diagnosis_suggestions (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid references public.encounters(id),
  suggested_icd text references public.icd_codes(code),
  reasoning text,
  model_version text,
  accepted boolean default false,
  created_at timestamptz default now()
);
