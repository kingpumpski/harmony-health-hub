-- Restore patient-hub record loading through an explicit, least-privilege RPC.
create or replace function public.get_patient_profile_for_user(_patient_id uuid)
returns table (
  id uuid, patient_code text, first_name text, last_name text, date_of_birth date,
  gender text, email text, phone text, address text, city text, ghana_card_number text,
  blood_group text, genotype text, allergies text, chronic_conditions text,
  insurance_provider text, insurance_number text, insurance_group_number text,
  insurance_expiry date, insurance_company_id uuid, emergency_contact_name text,
  emergency_contact_phone text, emergency_contact_relation text, status text
)
language plpgsql security definer set search_path = ''
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Authentication required'; end if;
  if not (
    public.has_role(uid, 'admin'::public.app_role) or
    public.has_role(uid, 'it_admin'::public.app_role) or
    public.has_role(uid, 'practitioner'::public.app_role) or
    public.has_role(uid, 'nurse'::public.app_role) or
    public.has_role(uid, 'midwife'::public.app_role) or
    public.has_role(uid, 'specialist_nurse'::public.app_role) or
    public.has_role(uid, 'lab_technician'::public.app_role) or
    public.has_role(uid, 'radiologist'::public.app_role) or
    public.has_role(uid, 'pharmacist'::public.app_role) or
    public.has_role(uid, 'accountant'::public.app_role) or
    public.has_role(uid, 'front_desk'::public.app_role) or
    public.has_role(uid, 'canteen'::public.app_role)
  ) then raise exception 'Not authorized to access the patient record'; end if;
  return query
  select p.id,p.patient_code,p.first_name,p.last_name,p.date_of_birth,p.gender::text,
    p.email,p.phone,p.address,p.city,p.ghana_card_number,p.blood_group::text,
    p.genotype::text,p.allergies,p.chronic_conditions,p.insurance_provider,
    p.insurance_number,p.insurance_group_number,p.insurance_expiry,p.insurance_company_id,
    p.emergency_contact_name,p.emergency_contact_phone,p.emergency_contact_relation,p.status::text
  from public.patients p
  where p.id = _patient_id
    and (p.user_id = uid or p.facility_id is null or public.current_user_has_facility_access(p.facility_id));
end;
$$;

revoke all on function public.get_patient_profile_for_user(uuid) from public, anon;
grant execute on function public.get_patient_profile_for_user(uuid) to authenticated;
notify pgrst, 'reload schema';