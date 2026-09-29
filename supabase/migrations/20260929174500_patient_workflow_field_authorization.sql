-- Harden patient mutation by making the existing JSONB API explicit, role-aware, and fail-closed.
create or replace function public.update_patient_workflow(_patient_id uuid, _changes jsonb)
returns public.patients
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  uid uuid := auth.uid();
  v_patient public.patients;
  v_role text;
  v_allowed_keys text[] := array[
    'patient_code','first_name','last_name','date_of_birth','gender','email','phone',
    'address','city','ghana_card_number','insurance_provider','insurance_number',
    'insurance_group_number','insurance_expiry','emergency_contact_name',
    'emergency_contact_phone','emergency_contact_relation','blood_group','genotype',
    'allergies','chronic_conditions','status'
  ];
  v_key text;
begin
  if uid is null then raise exception 'Authentication required'; end if;
  select ur.role::text into v_role
  from public.user_roles ur
  where ur.user_id = uid
  order by ur.created_at desc
  limit 1;

  if v_role is null then raise exception 'Staff profile required'; end if;
  if v_role not in ('admin','front_desk','nurse','practitioner','midwife') then
    raise exception 'Patient update is not permitted';
  end if;
  if _patient_id is null or _changes is null or jsonb_typeof(_changes) <> 'object' then
    raise exception 'Patient and changes are required';
  end if;

  -- Fail closed for unknown fields rather than silently ignoring client payload keys.
  for v_key in select jsonb_object_keys(_changes) loop
    if not (v_key = any(v_allowed_keys)) then
      raise exception 'Patient field is not permitted: %', v_key;
    end if;
  end loop;

  -- Front-desk demographic/administrative editing must not mutate clinical safety data.
  if v_role = 'front_desk' and (
    _changes ? 'blood_group' or _changes ? 'genotype' or
    _changes ? 'allergies' or _changes ? 'chronic_conditions'
  ) then
    raise exception 'Clinical patient fields require a clinical role';
  end if;

  -- Clinical roles may maintain clinical context but not administrative identity/status/insurance controls.
  if v_role in ('nurse','practitioner','midwife') and (
    _changes ? 'patient_code' or _changes ? 'ghana_card_number' or
    _changes ? 'insurance_provider' or _changes ? 'insurance_number' or
    _changes ? 'insurance_group_number' or _changes ? 'insurance_expiry' or
    _changes ? 'status'
  ) then
    raise exception 'Administrative patient fields require an administrative role';
  end if;

  if _changes ? 'status' and coalesce(_changes->>'status','') not in ('active','inactive','discharged') then
    raise exception 'Invalid patient status';
  end if;

  select * into v_patient
  from public.patients
  where id = _patient_id
  for update;

  if not found then raise exception 'Patient not found'; end if;

  update public.patients set
    patient_code = case when _changes ? 'patient_code' then nullif(pg_catalog.btrim(_changes->>'patient_code'),'') else patient_code end,
    first_name = case when _changes ? 'first_name' then nullif(pg_catalog.btrim(_changes->>'first_name'),'') else first_name end,
    last_name = case when _changes ? 'last_name' then nullif(pg_catalog.btrim(_changes->>'last_name'),'') else last_name end,
    date_of_birth = case when _changes ? 'date_of_birth' then nullif(_changes->>'date_of_birth','')::date else date_of_birth end,
    gender = case when _changes ? 'gender' then nullif(_changes->>'gender','') else gender end,
    email = case when _changes ? 'email' then nullif(_changes->>'email','') else email end,
    phone = case when _changes ? 'phone' then nullif(_changes->>'phone','') else phone end,
    address = case when _changes ? 'address' then nullif(_changes->>'address','') else address end,
    city = case when _changes ? 'city' then nullif(_changes->>'city','') else city end,
    ghana_card_number = case when _changes ? 'ghana_card_number' then nullif(_changes->>'ghana_card_number','') else ghana_card_number end,
    insurance_provider = case when _changes ? 'insurance_provider' then nullif(_changes->>'insurance_provider','') else insurance_provider end,
    insurance_number = case when _changes ? 'insurance_number' then nullif(_changes->>'insurance_number','') else insurance_number end,
    insurance_group_number = case when _changes ? 'insurance_group_number' then nullif(_changes->>'insurance_group_number','') else insurance_group_number end,
    insurance_expiry = case when _changes ? 'insurance_expiry' then nullif(_changes->>'insurance_expiry','')::date else insurance_expiry end,
    emergency_contact_name = case when _changes ? 'emergency_contact_name' then nullif(_changes->>'emergency_contact_name','') else emergency_contact_name end,
    emergency_contact_phone = case when _changes ? 'emergency_contact_phone' then nullif(_changes->>'emergency_contact_phone','') else emergency_contact_phone end,
    emergency_contact_relation = case when _changes ? 'emergency_contact_relation' then nullif(_changes->>'emergency_contact_relation','') else emergency_contact_relation end,
    blood_group = case when _changes ? 'blood_group' then nullif(_changes->>'blood_group','') else blood_group end,
    genotype = case when _changes ? 'genotype' then nullif(_changes->>'genotype','') else genotype end,
    allergies = case when _changes ? 'allergies' then nullif(_changes->>'allergies','') else allergies end,
    chronic_conditions = case when _changes ? 'chronic_conditions' then nullif(_changes->>'chronic_conditions','') else chronic_conditions end,
    status = case when _changes ? 'status' then nullif(_changes->>'status','') else status end,
    updated_at = now()
  where id = _patient_id
  returning * into v_patient;

  return v_patient;
end;
$function$;

revoke all on function public.update_patient_workflow(uuid,jsonb) from public, anon;
grant execute on function public.update_patient_workflow(uuid,jsonb) to authenticated;
