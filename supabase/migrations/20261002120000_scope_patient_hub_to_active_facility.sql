-- Keep patient directory and Patient Hub reads inside the active facility boundary.
-- A missing active facility is an actionable context error, not an empty patient record.

create or replace function public.search_patient_directory(
  _query text default null,
  _limit integer default 300
)
returns table (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  phone text,
  ghana_card_number text,
  status text,
  insurance_provider text,
  insurance_number text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  active_facility uuid;
  is_admin boolean;
  is_test_user boolean;
  test_facility uuid;
  can_sensitive boolean;
  q text := nullif(pg_catalog.btrim(coalesce(_query, '')), '');
  lim integer := least(greatest(coalesce(_limit, 100), 1), 1000);
begin
  if uid is null then
    raise exception 'Authentication required';
  end if;

  if not (
    public.has_role(uid, 'admin'::public.app_role)
    or public.has_role(uid, 'it_admin'::public.app_role)
    or public.has_role(uid, 'system_superuser'::public.app_role)
    or public.has_role(uid, 'practitioner'::public.app_role)
    or public.has_role(uid, 'nurse'::public.app_role)
    or public.has_role(uid, 'midwife'::public.app_role)
    or public.has_role(uid, 'specialist_nurse'::public.app_role)
    or public.has_role(uid, 'lab_technician'::public.app_role)
    or public.has_role(uid, 'radiologist'::public.app_role)
    or public.has_role(uid, 'radiology_technician'::public.app_role)
    or public.has_role(uid, 'pharmacist'::public.app_role)
    or public.has_role(uid, 'accountant'::public.app_role)
    or public.has_role(uid, 'front_desk'::public.app_role)
    or public.has_role(uid, 'canteen'::public.app_role)
  ) then
    raise exception 'Not authorized to access the staff patient directory';
  end if;

  is_admin := public.has_role(uid, 'admin'::public.app_role)
    or public.has_role(uid, 'it_admin'::public.app_role);
  is_test_user := public.hms_current_user_is_test_user();
  active_facility := public.current_user_facility_id();

  -- Test mode takes precedence over administrator privileges.
  if is_test_user then
    test_facility := public.hms_test_facility_id();
    if test_facility is null then
      raise exception 'Test mode is active but TEST-0001 is not configured';
    end if;
    active_facility := test_facility;
    is_admin := false;
  end if;

  if not is_admin and active_facility is null then
    raise exception 'An active facility is required to search patient records';
  end if;

  can_sensitive := public.has_role(uid, 'admin'::public.app_role)
    or public.has_role(uid, 'it_admin'::public.app_role)
    or public.has_role(uid, 'system_superuser'::public.app_role)
    or public.has_role(uid, 'practitioner'::public.app_role)
    or public.has_role(uid, 'nurse'::public.app_role)
    or public.has_role(uid, 'midwife'::public.app_role)
    or public.has_role(uid, 'specialist_nurse'::public.app_role)
    or public.has_role(uid, 'accountant'::public.app_role)
    or public.has_role(uid, 'front_desk'::public.app_role);

  return query
  select
    p.id,
    p.patient_code,
    p.first_name,
    p.last_name,
    p.phone,
    case when can_sensitive then p.ghana_card_number else null end,
    p.status::text,
    case when can_sensitive then p.insurance_provider else null end,
    case when can_sensitive then p.insurance_number else null end
  from public.patients p
  where
    coalesce(p.status, 'active') <> 'inactive'
    and (q is null
      or p.patient_code ilike '%' || q || '%'
      or p.first_name ilike '%' || q || '%'
      or p.last_name ilike '%' || q || '%'
      or p.phone ilike '%' || q || '%'
      or p.ghana_card_number ilike '%' || q || '%'
      or p.email ilike '%' || q || '%')
    and (
      is_admin
      or (
        p.facility_id = active_facility
        and public.current_user_has_facility_access(p.facility_id)
      )
    )
  order by p.created_at desc
  limit lim;
end;
$$;

revoke all on function public.search_patient_directory(text, integer) from public, anon;
grant execute on function public.search_patient_directory(text, integer) to authenticated;

create or replace function public.get_patient_profile_for_user(_patient_id uuid)
returns table (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  date_of_birth date,
  gender text,
  email text,
  phone text,
  address text,
  city text,
  ghana_card_number text,
  blood_group text,
  genotype text,
  allergies text,
  chronic_conditions text,
  insurance_provider text,
  insurance_number text,
  insurance_group_number text,
  insurance_expiry date,
  insurance_company_id uuid,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relation text,
  status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Authentication required';
  end if;

  if not (
    public.has_role(uid, 'admin'::public.app_role)
    or public.has_role(uid, 'it_admin'::public.app_role)
    or public.has_role(uid, 'system_superuser'::public.app_role)
    or public.has_role(uid, 'practitioner'::public.app_role)
    or public.has_role(uid, 'nurse'::public.app_role)
    or public.has_role(uid, 'midwife'::public.app_role)
    or public.has_role(uid, 'specialist_nurse'::public.app_role)
    or public.has_role(uid, 'lab_technician'::public.app_role)
    or public.has_role(uid, 'radiologist'::public.app_role)
    or public.has_role(uid, 'radiology_technician'::public.app_role)
    or public.has_role(uid, 'pharmacist'::public.app_role)
    or public.has_role(uid, 'accountant'::public.app_role)
    or public.has_role(uid, 'front_desk'::public.app_role)
    or public.has_role(uid, 'canteen'::public.app_role)
  ) then
    raise exception 'Not authorized to access the patient record';
  end if;

  -- The helper enforces TEST-0001 isolation before admin exceptions and
  -- requires system superusers to have the patient facility selected.
  perform public.assert_patient_facility_read_context(_patient_id);

  return query
  select
    p.id,
    p.patient_code,
    p.first_name,
    p.last_name,
    p.date_of_birth,
    p.gender::text,
    p.email,
    p.phone,
    p.address,
    p.city,
    p.ghana_card_number,
    p.blood_group::text,
    p.genotype::text,
    p.allergies,
    p.chronic_conditions,
    p.insurance_provider,
    p.insurance_number,
    p.insurance_group_number,
    p.insurance_expiry,
    p.insurance_company_id,
    p.emergency_contact_name,
    p.emergency_contact_phone,
    p.emergency_contact_relation,
    p.status::text
  from public.patients p
  where p.id = _patient_id
    and coalesce(p.status, 'active') <> 'inactive';
end;
$$;

revoke all on function public.get_patient_profile_for_user(uuid) from public, anon;
grant execute on function public.get_patient_profile_for_user(uuid) to authenticated;

create or replace function public.get_patient_directory_record(_patient_id uuid)
returns table (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  phone text,
  ghana_card_number text,
  status text,
  insurance_provider text,
  insurance_number text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  can_sensitive boolean;
begin
  if uid is null then
    raise exception 'Authentication required';
  end if;

  if not (
    public.has_role(uid, 'admin'::public.app_role)
    or public.has_role(uid, 'it_admin'::public.app_role)
    or public.has_role(uid, 'system_superuser'::public.app_role)
    or public.has_role(uid, 'practitioner'::public.app_role)
    or public.has_role(uid, 'nurse'::public.app_role)
    or public.has_role(uid, 'midwife'::public.app_role)
    or public.has_role(uid, 'specialist_nurse'::public.app_role)
    or public.has_role(uid, 'lab_technician'::public.app_role)
    or public.has_role(uid, 'radiologist'::public.app_role)
    or public.has_role(uid, 'radiology_technician'::public.app_role)
    or public.has_role(uid, 'pharmacist'::public.app_role)
    or public.has_role(uid, 'accountant'::public.app_role)
    or public.has_role(uid, 'front_desk'::public.app_role)
    or public.has_role(uid, 'canteen'::public.app_role)
  ) then
    raise exception 'Not authorized to access the staff patient directory';
  end if;

  perform public.assert_patient_facility_read_context(_patient_id);

  can_sensitive := public.has_role(uid, 'admin'::public.app_role)
    or public.has_role(uid, 'it_admin'::public.app_role)
    or public.has_role(uid, 'system_superuser'::public.app_role)
    or public.has_role(uid, 'practitioner'::public.app_role)
    or public.has_role(uid, 'nurse'::public.app_role)
    or public.has_role(uid, 'midwife'::public.app_role)
    or public.has_role(uid, 'specialist_nurse'::public.app_role)
    or public.has_role(uid, 'accountant'::public.app_role)
    or public.has_role(uid, 'front_desk'::public.app_role);

  return query
  select
    p.id,
    p.patient_code,
    p.first_name,
    p.last_name,
    p.phone,
    case when can_sensitive then p.ghana_card_number else null end,
    p.status::text,
    case when can_sensitive then p.insurance_provider else null end,
    case when can_sensitive then p.insurance_number else null end
  from public.patients p
  where p.id = _patient_id
    and coalesce(p.status, 'active') <> 'inactive';
end;
$$;

revoke all on function public.get_patient_directory_record(uuid) from public, anon;
grant execute on function public.get_patient_directory_record(uuid) to authenticated;

notify pgrst, 'reload schema';
