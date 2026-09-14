-- Keep the appointment lifecycle synchronized when its clinical encounter is completed.
-- This is deliberately additive: the existing encounter completion contract remains the
-- single clinical completion entrypoint, while the linked appointment is advanced atomically.
CREATE OR REPLACE FUNCTION public.complete_encounter_workflow(_encounter_id UUID)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  result public.encounters;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to complete encounters';
  END IF;

  SELECT * INTO result
  FROM public.encounters
  WHERE id = _encounter_id
  FOR UPDATE;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Encounter does not exist';
  END IF;

  IF result.status = 'completed' THEN
    RETURN result;
  END IF;

  IF result.principal_diagnosis IS NULL
     OR NULLIF(trim(result.principal_diagnosis),'') IS NULL THEN
    RAISE EXCEPTION 'Principal diagnosis required';
  END IF;

  UPDATE public.encounters
  SET status = 'completed',
      completed_at = COALESCE(completed_at, now()),
      updated_at = now()
  WHERE id = _encounter_id
  RETURNING * INTO result;

  IF result.appointment_id IS NOT NULL THEN
    UPDATE public.appointments
    SET treatment_status = 'completed',
        completed_at = COALESCE(completed_at, now()),
        status = CASE
          WHEN status IN ('cancelled','no_show') THEN status
          ELSE 'completed'
        END,
        updated_at = now()
    WHERE id = result.appointment_id
      AND treatment_status NOT IN ('cancelled','no_show');
  END IF;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_encounter_workflow(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_encounter_workflow(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
