-- Narrow appointment creation to the roles explicitly authorized by the
-- underlying appointment workflow. Do not use the legacy broad clinical helper
-- because it includes non-care roles.

CREATE OR REPLACE FUNCTION public.create_patient_appointment(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT DEFAULT NULL,
  _reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'front_desk')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
  ) THEN
    RAISE EXCEPTION 'Appointment creation denied';
  END IF;

  RETURN jsonb_build_object(
    'appointment_id', (
      public.create_appointment_workflow(
        _patient_id,
        _scheduled_at,
        _department,
        _reason
      )
    ).id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;
