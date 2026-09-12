-- Medication reminders repeat every 15 minutes while a scheduled dose remains overdue.
CREATE OR REPLACE FUNCTION public.notify_due_medications()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r RECORD; n INTEGER:=0; bucket TEXT; elapsed_minutes INTEGER;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  FOR r IN
    SELECT m.*,p.first_name,p.last_name
    FROM public.medication_administrations m
    JOIN public.patients p ON p.id=m.patient_id
    WHERE m.status='scheduled' AND m.scheduled_at IS NOT NULL AND m.locked_at IS NULL
      AND m.scheduled_at <= now() + interval '15 minutes'
      AND m.scheduled_at >= now() - make_interval(mins => m.due_window_minutes)
  LOOP
    elapsed_minutes := GREATEST(0,FLOOR(EXTRACT(EPOCH FROM (now()-r.scheduled_at))/60)::INTEGER);
    bucket := CASE WHEN r.scheduled_at > now() THEN 'upcoming_15m' ELSE 'overdue_15m_' || FLOOR(elapsed_minutes/15)::INTEGER::TEXT END;
    INSERT INTO public.medication_due_notification_log(medication_administration_id,recipient_user_id,reminder_bucket)
    SELECT r.id,s.user_id,bucket
    FROM public.staff_shift_assignments s
    WHERE s.active AND lower(s.department) IN ('nursing','nurse','midwifery','midwife')
      AND s.starts_at <= now() AND s.ends_at >= now()
    ON CONFLICT DO NOTHING;

    INSERT INTO public.notifications(recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
    SELECT s.user_id,'Medication due',r.medication_name||' for '||r.first_name||' '||r.last_name||' is due now or remains overdue.',
      'warning','prescription','/medications',r.patient_id,r.id,
      jsonb_build_object('scheduled_at',r.scheduled_at,'reminder_bucket',bucket,'department',s.department)
    FROM public.staff_shift_assignments s
    WHERE s.active AND lower(s.department) IN ('nursing','nurse','midwifery','midwife')
      AND s.starts_at <= now() AND s.ends_at >= now()
      AND EXISTS (SELECT 1 FROM public.medication_due_notification_log l WHERE l.medication_administration_id=r.id AND l.recipient_user_id=s.user_id AND l.reminder_bucket=bucket)
      AND NOT EXISTS (SELECT 1 FROM public.notifications x WHERE x.recipient_user_id=s.user_id AND x.related_entity_id=r.id AND x.metadata->>'reminder_bucket'=bucket);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_due_medications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_due_medications() TO authenticated;
