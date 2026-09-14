-- Restore the diagnosis search RPC used by clinician autocomplete.
-- The canonical production function is recreated with a stable return contract.

drop function if exists public.search_clinical_diagnoses(text, uuid, integer);

create function public.search_clinical_diagnoses(
  _query text,
  _facility_id uuid default null,
  _limit integer default 12
)
returns table (
  display_name text,
  code text,
  source text,
  standard_name text,
  icd10_code text
)
language sql stable security invoker
set search_path = public
as $$
  with active_standards as (
    select ds.id, ds.name, coalesce(fds.priority, 1000) as priority
    from public.diagnosis_standards ds
    left join public.facility_diagnosis_standards fds
      on fds.standard_id = ds.id
     and fds.facility_id = _facility_id
     and fds.is_active = true
    where ds.is_active = true
      and (
        _facility_id is null
        or fds.standard_id is not null
        or ds.code = 'GH-STG'
        or ds.code ilike 'ICD%'
      )
  ),
  stg as (
    select sd.display_name, sd.code, ds.name as source, ds.name as standard_name,
           icd.code as icd10_code, 1 as source_rank, a.priority
    from public.stg_diagnoses sd
    join active_standards a on a.id = sd.standard_id
    join public.diagnosis_standards ds on ds.id = sd.standard_id
    left join public.icd_codes icd on icd.id = sd.icd10_code_id
    where sd.is_active = true
      and (
        sd.display_name ilike '%' || _query || '%'
        or sd.code ilike '%' || _query || '%'
        or coalesce(sd.description, '') ilike '%' || _query || '%'
        or exists (select 1 from unnest(sd.synonyms) s where s ilike '%' || _query || '%')
      )
  ),
  icd as (
    select icd.description, icd.code, 'ICD-10'::text,
           coalesce(icd.version, 'ICD-10'), icd.code, 2, 1000
    from public.icd_codes icd
    where icd.description ilike '%' || _query || '%'
       or icd.code ilike '%' || _query || '%'
  )
  select display_name, code, source, standard_name, icd10_code
  from (select * from stg union all select * from icd) results
  order by source_rank, priority, display_name
  limit greatest(1, least(coalesce(_limit, 12), 50));
$$;

grant execute on function public.search_clinical_diagnoses(text, uuid, integer) to authenticated;
revoke execute on function public.search_clinical_diagnoses(text, uuid, integer) from anon;

create index if not exists stg_diagnoses_standard_active_idx
  on public.stg_diagnoses(standard_id, is_active);
create index if not exists stg_diagnoses_code_idx
  on public.stg_diagnoses(code);
create index if not exists stg_diagnoses_display_name_idx
  on public.stg_diagnoses(display_name);

notify pgrst, 'reload schema';
