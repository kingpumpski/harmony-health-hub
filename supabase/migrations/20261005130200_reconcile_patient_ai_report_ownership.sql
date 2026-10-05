-- Allow patient-owned AI report requests when legacy test records have no user_id but match authenticated email.
create or replace function public.create_ai_report_request(_patient_id uuid,_report_type text default 'medical_summary')
returns public.ai_report_requests
language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); v_report public.ai_report_requests; v_type text:=lower(pg_catalog.btrim(coalesce(_report_type,'medical_summary'))); v_email text:=lower(nullif(trim((auth.jwt()->>'email')),''));
begin
 if uid is null then raise exception 'Authentication required'; end if;
 if _patient_id is null then raise exception 'Patient is required'; end if;
 perform public.assert_patient_facility_context(_patient_id);
 if not exists(select 1 from public.patients p where p.id=_patient_id and (p.user_id=uid or (p.user_id is null and v_email is not null and lower(p.email)=v_email) or public.has_role(uid,'admin') or public.has_role(uid,'it_admin') or public.has_role(uid,'practitioner') or public.has_role(uid,'nurse') or public.has_role(uid,'midwife') or public.has_role(uid,'specialist_nurse') or public.has_role(uid,'radiologist'))) then raise exception 'Not authorised to request this patient report'; end if;
 if v_type<>'medical_summary' then raise exception 'Unsupported report type'; end if;
 insert into public.ai_report_requests(patient_id,requested_by,report_type,status) values(_patient_id,uid,v_type,'processing') returning * into v_report;
 return v_report;
end; $$;
revoke all on function public.create_ai_report_request(uuid,text) from public,anon;
grant execute on function public.create_ai_report_request(uuid,text) to authenticated;
