-- Least-privilege Patient Hub clinical snapshot boundary.
-- Core clinical roles receive the full snapshot.
-- Laboratory staff receive laboratory history only.
-- Pharmacy staff receive prescription history only.
-- Radiology roles use patient directory/appointment and imaging-specific workflows,
-- not the longitudinal clinical snapshot.

create or replace function public.get_patient_hub_clinical_snapshot(_patient_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  is_core boolean;
  is_lab boolean;
  is_pharmacy boolean;
begin
  if uid is null then
    raise exception 'Authentication required';
  end if;

  is_core :=
    public.has_role(uid,'admin') or
    public.has_role(uid,'practitioner') or
    public.has_role(uid,'nurse') or
    public.has_role(uid,'midwife') or
    public.has_role(uid,'specialist_nurse');

  is_lab := public.has_role(uid,'lab_technician');
  is_pharmacy := public.has_role(uid,'pharmacist');

  if not (is_core or is_lab or is_pharmacy) then
    raise exception 'Not authorized to access patient clinical history';
  end if;

  if _patient_id is null
     or not exists (
       select 1
       from public.patients
       where id = _patient_id
         and status <> 'inactive'
     )
  then
    raise exception 'Patient not found or inactive';
  end if;

  return jsonb_build_object(
    'vitals',
      case when is_core then
        coalesce((
          select jsonb_agg(to_jsonb(x) order by x.recorded_at desc)
          from (
            select id, recorded_at, systolic, diastolic, pulse_rate,
                   temperature, respiratory_rate, oxygen_saturation,
                   weight_kg, height_cm, bmi, priority, notes, encounter_id
            from public.vital_signs
            where patient_id = _patient_id
            order by recorded_at desc
            limit 100
          ) x
        ), '[]'::jsonb)
      else '[]'::jsonb end,

    'encounters',
      case when is_core then
        coalesce((
          select jsonb_agg(to_jsonb(x) order by x.created_at desc)
          from (
            select id, created_at, status, encounter_type, chief_complaint,
                   symptoms, clerking_notes, principal_diagnosis,
                   treatment_plan, follow_up_date, practitioner_id,
                   provider_id, admission_id, started_at, completed_at
            from public.encounters
            where patient_id = _patient_id
            order by created_at desc
            limit 100
          ) x
        ), '[]'::jsonb)
      else '[]'::jsonb end,

    'labs',
      case when is_core or is_lab then
        coalesce((
          select jsonb_agg(to_jsonb(x) order by x.created_at desc)
          from (
            select id, created_at, test_name, test_category, priority,
                   clinical_notes, status, sample_collected_at,
                   collected_by, encounter_id, ordered_by
            from public.lab_orders
            where patient_id = _patient_id
            order by created_at desc
            limit 100
          ) x
        ), '[]'::jsonb)
      else '[]'::jsonb end,

    'prescriptions',
      case when is_core or is_pharmacy then
        coalesce((
          select jsonb_agg(to_jsonb(x) order by x.created_at desc)
          from (
            select id, created_at, medication, medication_name, dosage,
                   frequency, duration, route, status, encounter_id,
                   prescribed_by, dispensed_at
            from public.prescriptions
            where patient_id = _patient_id
            order by created_at desc
            limit 100
          ) x
        ), '[]'::jsonb)
      else '[]'::jsonb end,

    'documents',
      case when is_core then
        coalesce((
          select jsonb_agg(to_jsonb(x) order by x.created_at desc)
          from (
            select id, created_at, document_type, file_name, storage_path,
                   mime_type, file_size, notes, uploaded_by
            from public.patient_documents
            where patient_id = _patient_id
            order by created_at desc
            limit 100
          ) x
        ), '[]'::jsonb)
      else '[]'::jsonb end
  );
end;
$function$;

revoke all on function public.get_patient_hub_clinical_snapshot(uuid) from public, anon;
grant execute on function public.get_patient_hub_clinical_snapshot(uuid) to authenticated;
