-- Harden the governed STG-Ghana import workflow.
-- Missing source codes are rejected rather than synthesized.
-- All staged rows, including blank-name rows, are classified during validation.

create or replace function public.validate_diagnosis_import_batch(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_total integer;
  v_accepted integer;
  v_rejected integer;
  v_duplicate integer;
  v_unmapped integer;
begin
  if not public.has_role(auth.uid(), 'admin') then raise exception 'admin access required'; end if;
  if not exists (select 1 from public.diagnosis_import_batches where id=p_batch_id) then raise exception 'import batch not found'; end if;

  with ranked as (
    select id, row_number() over (
      partition by nullif(lower(regexp_replace(trim(coalesce(display_name,'')), '\\s+', ' ', 'g')), '')
      order by id
    ) rn
    from public.diagnosis_import_rows
    where batch_id=p_batch_id
  )
  update public.diagnosis_import_rows r
  set row_status=case
      when coalesce(nullif(trim(r.display_name),''),'') = '' then 'rejected'
      when coalesce(nullif(trim(r.source_code),''),'') = '' then 'rejected'
      when ranked.rn>1 then 'duplicate'
      when r.icd10_code is not null and trim(r.icd10_code) <> '' and not exists (
        select 1 from public.icd_codes i where upper(trim(i.code))=upper(trim(r.icd10_code))
      ) then 'unmapped'
      else 'accepted' end,
    rejection_reason=case
      when coalesce(nullif(trim(r.display_name),''),'') = '' then 'missing diagnosis name'
      when coalesce(nullif(trim(r.source_code),''),'') = '' then 'missing source diagnosis code'
      when ranked.rn>1 then 'duplicate normalized diagnosis'
      when r.icd10_code is not null and trim(r.icd10_code) <> '' and not exists (
        select 1 from public.icd_codes i where upper(trim(i.code))=upper(trim(r.icd10_code))
      ) then 'ICD-10 code not found in local ICD catalogue'
      else null end,
    icd10_code_id=(select i.id from public.icd_codes i where upper(trim(i.code))=upper(trim(r.icd10_code)) limit 1),
    normalized_key=lower(regexp_replace(trim(coalesce(r.display_name,'')), '\\s+', ' ', 'g'))
  from ranked where r.id=ranked.id;

  update public.diagnosis_import_batches b
  set accepted_rows=(select count(*) from public.diagnosis_import_rows where batch_id=p_batch_id and row_status='accepted'),
      rejected_rows=(select count(*) from public.diagnosis_import_rows where batch_id=p_batch_id and row_status='rejected'),
      duplicate_rows=(select count(*) from public.diagnosis_import_rows where batch_id=p_batch_id and row_status='duplicate'),
      unmapped_rows=(select count(*) from public.diagnosis_import_rows where batch_id=p_batch_id and row_status='unmapped'),
      status='validated'
  where b.id=p_batch_id;

  select total_rows,accepted_rows,rejected_rows,duplicate_rows,unmapped_rows
    into v_total,v_accepted,v_rejected,v_duplicate,v_unmapped
  from public.diagnosis_import_batches where id=p_batch_id;
  return jsonb_build_object('batch_id',p_batch_id,'status','validated','total_rows',v_total,'accepted_rows',v_accepted,'rejected_rows',v_rejected,'duplicate_rows',v_duplicate,'unmapped_rows',v_unmapped);
end; $$;

create or replace function public.import_approved_diagnosis_batch(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_standard uuid;
  v_inserted integer;
begin
  if not public.has_role(auth.uid(), 'admin') then raise exception 'admin access required'; end if;
  select standard_id into v_standard
  from public.diagnosis_import_batches
  where id=p_batch_id and status='approved'
  for update;
  if v_standard is null then raise exception 'approved batch not found'; end if;

  update public.diagnosis_import_batches set status='importing' where id=p_batch_id;
  insert into public.stg_diagnoses(standard_id,code,display_name,description,category,synonyms,icd10_code_id,source_reference,is_active)
  select v_standard,trim(source_code),display_name,description,category,synonyms,icd10_code_id,
         coalesce(sheet_name,'workbook')||':row:'||source_row_number,true
  from public.diagnosis_import_rows r
  where r.batch_id=p_batch_id and r.row_status='accepted'
    and not exists (
      select 1 from public.stg_diagnoses d
      where d.standard_id=v_standard and lower(d.display_name)=lower(r.display_name)
    );
  get diagnostics v_inserted = row_count;
  update public.diagnosis_import_batches
    set status='completed',completed_at=now(),accepted_rows=v_inserted
  where id=p_batch_id;
  return jsonb_build_object('batch_id',p_batch_id,'status','completed','inserted_rows',v_inserted);
exception when others then
  update public.diagnosis_import_batches
    set status='failed',validation_errors=coalesce(validation_errors,'[]'::jsonb)||jsonb_build_object('error',sqlerrm)
  where id=p_batch_id;
  raise;
end; $$;

revoke all on function public.validate_diagnosis_import_batch(uuid) from public;
revoke all on function public.approve_diagnosis_import_batch(uuid) from public;
revoke all on function public.import_approved_diagnosis_batch(uuid) from public;
grant execute on function public.validate_diagnosis_import_batch(uuid) to authenticated;
grant execute on function public.approve_diagnosis_import_batch(uuid) to authenticated;
grant execute on function public.import_approved_diagnosis_batch(uuid) to authenticated;
notify pgrst, 'reload schema';
