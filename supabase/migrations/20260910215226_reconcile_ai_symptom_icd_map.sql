-- Restore the canonical symptom-to-ICD reference table before RLS hardening.
create table if not exists public.ai_symptom_icd_map (
  id uuid primary key default gen_random_uuid(),
  confidence numeric,
  created_at timestamptz default now(),
  icd_code text references public.icd_codes(code),
  symptom text not null
);
