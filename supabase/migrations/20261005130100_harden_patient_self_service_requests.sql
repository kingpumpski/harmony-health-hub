-- Patient self-service appointment and notification boundary.
create or replace function public.create_patient_appointment(
  _patient_id uuid,_scheduled_at timestamptz,_department text default null,_reason text default null
)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare uid uuid:=auth.uid(); pf uuid; v_id uuid; is_patient boolean; own boolean;
begin
 if uid is null then raise exception 'Authentication required'; end if;
 is_patient:=public.has_role(uid,'patient');
 own:=exists(select 1 from public.patients p where p.id=_patient_id and (p.user_id=uid or (p.user_id is null and lower(p.email)=lower((auth.jwt()->>'email')))));
 if is_patient and not own then raise exception 'You may only request appointments for your own patient record'; end if;
 if not is_patient and not (public.has_role(uid,'admin') or public.has_role(uid,'it_admin') or public.has_role(uid,'front_desk') or public.has_role(uid,'practitioner') or public.has_role(uid,'nurse') or public.has_role(uid,'midwife')) then raise exception 'Appointment creation denied'; end if;
 pf:=public.assert_patient_facility_context(_patient_id);
 if _scheduled_at is null or _scheduled_at <= now() then raise exception 'A future appointment time is required'; end if;
 v_id:=(public.create_appointment_workflow(_patient_id,_scheduled_at,coalesce(nullif(trim(_department),''),'Clinical Consultation'),_reason)).id;
 return pg_catalog.jsonb_build_object('appointment_id',v_id,'facility_id',pf);
end;
$$;

drop policy if exists "users see notifications for their role or themselves" on public.notifications;
create policy "users see notifications for their role or themselves" on public.notifications for select to authenticated
using (
  recipient_user_id=(select auth.uid())
  or (
    recipient_role is not null
    and current_user_has_role(recipient_role)
    and not current_user_has_role('patient')
  )
);
revoke all on function public.create_patient_appointment(uuid,timestamptz,text,text) from public,anon;
grant execute on function public.create_patient_appointment(uuid,timestamptz,text,text) to authenticated;
