-- Appointment scheduling is an operational workflow suitable for an explicit
-- offline contract. Authorization remains server-side and the client supplies
-- a stable UUID to make replay after a lost response idempotent.
CREATE OR REPLACE FUNCTION public.create_patient_appointment_offline(
  _id UUID,
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT DEFAULT NULL,
  _reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing UUID;
BEGIN
  IF NOT (
    has_role(auth.uid(),'admin') OR
    has_role(auth.uid(),'practitioner') OR
    has_role(auth.uid(),'nurse') OR
    has_role(auth.uid(),'midwife') OR
    has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Appointment creation is not permitted';
  END IF;

  SELECT id INTO v_existing FROM public.appointments WHERE id = _id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('appointment_id', v_existing, 'already_recorded', true);
  END IF;

  INSERT INTO public.appointments (id, patient_id, scheduled_at, department, reason, status)
  VALUES (_id, _patient_id, _scheduled_at, _department, _reason, 'scheduled');

  RETURN jsonb_build_object('appointment_id', _id, 'already_recorded', false);
END;
$$;

REVOKE ALL ON FUNCTION public.create_patient_appointment_offline(UUID,UUID,TIMESTAMPTZ,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment_offline(UUID,UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;
