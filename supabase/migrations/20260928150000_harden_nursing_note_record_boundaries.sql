-- The nursing-note table is required by the RPC and later facility/index
-- migrations, but was missing from the clean migration chain. Keep this
-- compatibility creation idempotent for environments where it already exists.
CREATE TABLE IF NOT EXISTS public.nursing_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE RESTRICT,
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  encounter_id uuid REFERENCES public.encounters(id) ON DELETE RESTRICT,
  admission_id uuid REFERENCES public.admissions(id) ON DELETE RESTRICT,
  author_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  note_type text NOT NULL DEFAULT 'progress',
  note_text text NOT NULL,
  assessment text,
  intervention text,
  evaluation text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nursing_notes_encounter_or_admission_required
    CHECK (encounter_id IS NOT NULL OR admission_id IS NOT NULL)
);

ALTER TABLE public.nursing_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nursing_notes_read_current_facility
  ON public.nursing_notes;
CREATE POLICY nursing_notes_read_current_facility
  ON public.nursing_notes
  FOR SELECT
  TO authenticated
  USING (
    facility_id IS NOT NULL
    AND facility_id = (SELECT public.current_user_facility_id())
  );

-- Harden nursing-note creation so authenticated clinical writers cannot
-- attach a note to an unrelated encounter or admission.
CREATE OR REPLACE FUNCTION public.create_nursing_note(
  _patient_id uuid,
  _note_text text,
  _note_type text DEFAULT 'progress',
  _assessment text DEFAULT NULL,
  _intervention text DEFAULT NULL,
  _evaluation text DEFAULT NULL,
  _encounter_id uuid DEFAULT NULL,
  _admission_id uuid DEFAULT NULL
)
RETURNS public.nursing_notes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v public.nursing_notes;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.current_user_has_role('admin'::public.app_role)
    OR public.current_user_has_role('nurse'::public.app_role)
    OR public.current_user_has_role('specialist_nurse'::public.app_role)
    OR public.current_user_has_role('midwife'::public.app_role)
    OR public.current_user_has_role('practitioner'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Nursing documentation is not permitted for this role';
  END IF;

  IF NULLIF(pg_catalog.btrim(_note_text),'') IS NULL THEN
    RAISE EXCEPTION 'Nursing note text is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.patients p
    WHERE p.id = _patient_id
      AND COALESCE(p.status,'active') <> 'inactive'
  ) THEN
    RAISE EXCEPTION 'Patient not found or inactive';
  END IF;

  IF _encounter_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.encounters e
       WHERE e.id = _encounter_id
         AND e.patient_id = _patient_id
     )
  THEN
    RAISE EXCEPTION 'Encounter does not belong to this patient';
  END IF;

  IF _admission_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.admissions a
       WHERE a.id = _admission_id
         AND a.patient_id = _patient_id
     )
  THEN
    RAISE EXCEPTION 'Admission does not belong to this patient';
  END IF;

  IF _encounter_id IS NULL
     AND _admission_id IS NULL
  THEN
    RAISE EXCEPTION 'A nursing note must be linked to an encounter or admission';
  END IF;

  INSERT INTO public.nursing_notes(
    facility_id,
    patient_id,
    encounter_id,
    admission_id,
    author_id,
    note_type,
    note_text,
    assessment,
    intervention,
    evaluation
  )
  VALUES(
    public.current_user_facility_id(),
    _patient_id,
    _encounter_id,
    _admission_id,
    auth.uid(),
    COALESCE(NULLIF(pg_catalog.btrim(_note_type),''),'progress'),
    pg_catalog.btrim(_note_text),
    NULLIF(pg_catalog.btrim(_assessment),''),
    NULLIF(pg_catalog.btrim(_intervention),''),
    NULLIF(pg_catalog.btrim(_evaluation),'')
  )
  RETURNING * INTO v;

  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_nursing_note(
  uuid,text,text,text,text,text,uuid,uuid
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_nursing_note(
  uuid,text,text,text,text,text,uuid,uuid
) TO authenticated;
