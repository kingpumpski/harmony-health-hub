-- Reconcile the appointment clinician/worklist RPC contract with the current Appointments UI.
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS consultation_type TEXT NOT NULL DEFAULT 'General Consultation';

CREATE INDEX IF NOT EXISTS idx_appointments_practitioner_schedule
  ON public.appointments(practitioner_id, scheduled_at DESC);

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT,
  _consultation_type TEXT,
  _practitioner_id UUID DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(),'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to schedule appointments'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id AND COALESCE(status,'active') <> 'inactive') THEN RAISE EXCEPTION 'Active patient does not exist'; END IF;
  IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Scheduled time is required'; END IF;
  IF NULLIF(trim(_consultation_type),'') IS NULL THEN RAISE EXCEPTION 'Consultation type is required'; END IF;
  IF _practitioner_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=_practitioner_id) THEN RAISE EXCEPTION 'Selected clinician does not exist'; END IF;
  INSERT INTO public.appointments(patient_id, practitioner_id, department, scheduled_at, duration_minutes, reason, status, notes, created_at, updated_at, treatment_status, consultation_type)
  VALUES(_patient_id, _practitioner_id, NULLIF(trim(_department),''), _scheduled_at, 30, NULLIF(trim(_reason),''), 'scheduled', NULL, now(), now(), 'scheduled', NULLIF(trim(_consultation_type),''))
  RETURNING * INTO result;
  RETURN result;
END; $$;

GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_appointment_clinicians()
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, department TEXT, specialization TEXT, clinician_role TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(),'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Appointment clinician directory access denied'; END IF;
  RETURN QUERY
  SELECT DISTINCT p.id,p.first_name,p.last_name,p.department,p.specialization,ur.role::text
  FROM public.profiles p
  JOIN public.user_roles ur ON ur.user_id=p.id
  WHERE ur.role IN ('practitioner'::public.app_role,'radiologist'::public.app_role)
  ORDER BY p.last_name,p.first_name;
END; $$;
REVOKE ALL ON FUNCTION public.get_appointment_clinicians() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_clinicians() TO authenticated;

-- Backward-compatible singular RPC for clients/builds that still call the original contract.
CREATE OR REPLACE FUNCTION public.get_appointment_clinician()
RETURNS TABLE(id UUID, first_name TEXT, last_name TEXT, department TEXT, specialization TEXT, clinician_role TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
BEGIN
  RETURN QUERY SELECT * FROM public.get_appointment_clinicians();
END; $$;
REVOKE ALL ON FUNCTION public.get_appointment_clinician() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_clinician() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_appointment_worklist(_limit INTEGER DEFAULT 300)
RETURNS TABLE(
  id UUID,
  patient_id UUID,
  patient_code TEXT,
  patient_first_name TEXT,
  patient_last_name TEXT,
  scheduled_at TIMESTAMPTZ,
  consultation_type TEXT,
  practitioner_id UUID,
  practitioner_name TEXT,
  department TEXT,
  reason TEXT,
  status TEXT,
  attending_officer_id UUID,
  treatment_status TEXT,
  treatment_notes TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE v_limit INTEGER:=greatest(1,least(coalesce(_limit,300),500));
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(),'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Appointment worklist access denied'; END IF;
  RETURN QUERY
  SELECT a.id,a.patient_id,p.patient_code,p.first_name,p.last_name,a.scheduled_at,
    COALESCE(a.consultation_type,'General Consultation'),a.practitioner_id,
    NULLIF(trim(concat_ws(' ',pr.first_name,pr.last_name)),''),a.department,a.reason,a.status,
    a.attending_officer_id,a.treatment_status,a.treatment_notes
  FROM public.appointments a
  JOIN public.patients p ON p.id=a.patient_id
  LEFT JOIN public.profiles pr ON pr.id=a.practitioner_id
  WHERE COALESCE(p.status,'active') <> 'inactive'
  ORDER BY a.scheduled_at ASC
  LIMIT v_limit;
END; $$;
REVOKE ALL ON FUNCTION public.get_appointment_worklist(INTEGER) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_worklist(INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';