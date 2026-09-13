-- Phase 8 clinical flow: appointment -> encounter linkage.
ALTER TABLE public.encounters
  ADD COLUMN IF NOT EXISTS appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_encounters_appointment_id
  ON public.encounters(appointment_id);

-- One appointment should normally have one clinical encounter. This is partial so
-- historical encounters without an appointment remain valid.
CREATE UNIQUE INDEX IF NOT EXISTS uq_encounters_appointment_id
  ON public.encounters(appointment_id)
  WHERE appointment_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.start_appointment_encounter(
  _appointment_id UUID,
  _symptoms TEXT DEFAULT NULL,
  _clerking_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_role TEXT;
  v_patient UUID;
  v_existing UUID;
  v_encounter UUID;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT role::TEXT INTO v_role
  FROM public.profiles
  WHERE id = v_user;

  IF v_role NOT IN ('admin','practitioner','nurse','midwife','specialist_nurse') THEN
    RAISE EXCEPTION 'You are not authorized to start a clinical encounter';
  END IF;

  SELECT patient_id INTO v_patient
  FROM public.appointments
  WHERE id = _appointment_id
  FOR UPDATE;

  IF v_patient IS NULL THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;

  SELECT id INTO v_existing
  FROM public.encounters
  WHERE appointment_id = _appointment_id
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    UPDATE public.appointments
    SET attending_officer_id = COALESCE(attending_officer_id, v_user),
        claimed_at = COALESCE(claimed_at, NOW()),
        treatment_status = CASE
          WHEN treatment_status IN ('scheduled','claimed') THEN 'in_progress'
          ELSE treatment_status
        END,
        started_at = COALESCE(started_at, NOW()),
        updated_at = NOW()
    WHERE id = _appointment_id;
    RETURN v_existing;
  END IF;

  INSERT INTO public.encounters (
    patient_id,
    appointment_id,
    symptoms,
    clerking_notes,
    practitioner_id,
    status
  ) VALUES (
    v_patient,
    _appointment_id,
    NULLIF(_symptoms, ''),
    NULLIF(_clerking_notes, ''),
    v_user,
    'draft'
  )
  RETURNING id INTO v_encounter;

  UPDATE public.appointments
  SET attending_officer_id = v_user,
      claimed_at = COALESCE(claimed_at, NOW()),
      treatment_status = 'in_progress',
      started_at = COALESCE(started_at, NOW()),
      updated_at = NOW()
  WHERE id = _appointment_id;

  RETURN v_encounter;
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(UUID, TEXT, TEXT) TO authenticated;
