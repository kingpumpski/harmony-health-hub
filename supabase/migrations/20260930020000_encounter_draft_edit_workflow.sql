-- Persist edits made to an existing encounter draft.
-- Draft authoring remains server-authoritative; finalized encounters remain immutable
-- except through the existing amendment workflow.

create or replace function public.update_encounter_draft_workflow(
  _encounter_id uuid,
  _symptoms text default null,
  _clerking_notes text default null,
  _treatment_plan text default null
)
returns public.encounters
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  uid uuid := auth.uid();
  v_enc public.encounters%rowtype;
  result public.encounters;
begin
  if uid is null then
    raise exception 'Authentication required';
  end if;

  select *
    into v_enc
  from public.encounters
  where id = _encounter_id
  for update;

  if v_enc.id is null then
    raise exception 'Encounter not found';
  end if;

  if v_enc.status in ('completed','cancelled') then
    raise exception 'Completed or cancelled encounters are read-only';
  end if;

  if not (
    v_enc.practitioner_id = uid
    or public.has_role(uid,'admin')
    or public.has_role(uid,'it_admin')
  ) then
    raise exception 'Only the encounter creator or an administrator can edit this draft';
  end if;

  if not (
    public.has_role(uid,'admin')
    or public.has_role(uid,'it_admin')
    or public.has_role(uid,'practitioner')
    or public.has_role(uid,'nurse')
    or public.has_role(uid,'midwife')
    or public.has_role(uid,'specialist_nurse')
  ) then
    raise exception 'Clinical authorization required';
  end if;

  if nullif(pg_catalog.btrim(coalesce(_symptoms,'')),'') is null
     and nullif(pg_catalog.btrim(coalesce(_clerking_notes,'')),'') is null
     and nullif(pg_catalog.btrim(coalesce(_treatment_plan,'')),'') is null
     and not exists (
       select 1
       from public.diagnoses d
       where d.encounter_id = v_enc.id
     )
     and not exists (
       select 1
       from public.prescriptions p
       where p.encounter_id = v_enc.id
     ) then
    raise exception 'Encounter clinical information is required';
  end if;

  update public.encounters
  set symptoms = nullif(pg_catalog.btrim(_symptoms),''),
      clerking_notes = nullif(pg_catalog.btrim(_clerking_notes),''),
      treatment_plan = nullif(pg_catalog.btrim(_treatment_plan),''),
      updated_at = now()
  where id = v_enc.id
  returning * into result;

  perform public.record_system_audit(
    'encounter_draft_saved',
    'clinical',
    'encounter',
    v_enc.id,
    'info',
    jsonb_build_object(
      'patient_id', v_enc.patient_id,
      'saved_by', uid,
      'status', result.status
    )
  );

  return result;
end;
$function$;

revoke all on function public.update_encounter_draft_workflow(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.update_encounter_draft_workflow(uuid,text,text,text) to authenticated;

notify pgrst, 'reload schema';
