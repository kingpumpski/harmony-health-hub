-- Gate A: harden the encounter workflow workspace read path.
-- The workspace is SECURITY DEFINER because it composes protected encounter/patient
-- data. Test mode must remain isolated to TEST-0001 before any privileged role exception.

CREATE OR REPLACE FUNCTION public.get_encounter_workflow_workspace()
RETURNS TABLE(
  encounter_id uuid,
  patient_id uuid,
  patient_name text,
  patient_code text,
  status text,
  version_no integer,
  admission_id uuid,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    e.id,
    e.patient_id,
    concat(p.first_name, ' ', p.last_name),
    p.patient_code,
    e.status,
    e.version_no,
    e.admission_id,
    e.created_at
  FROM public.encounters e
  JOIN public.patients p ON p.id = e.patient_id
  WHERE auth.uid() IS NOT NULL
    AND (
      public.current_user_has_role('admin'::public.app_role)
      OR public.current_user_has_role('practitioner'::public.app_role)
      OR public.current_user_has_role('nurse'::public.app_role)
      OR public.current_user_has_role('midwife'::public.app_role)
      OR public.current_user_has_role('specialist_nurse'::public.app_role)
    )
    AND (
      (
        public.hms_test_mode_enabled()
        AND e.facility_id = public.hms_test_facility_id()
        AND p.facility_id = public.hms_test_facility_id()
      )
      OR (
        NOT public.hms_test_mode_enabled()
        AND (
          public.current_user_has_role('admin'::public.app_role)
          OR (
            e.facility_id = public.current_user_facility_id()
            AND p.facility_id = public.current_user_facility_id()
          )
        )
      )
    )
    AND (
      public.current_user_has_role('admin'::public.app_role)
      OR e.practitioner_id = auth.uid()
      OR e.practitioner_id IS NULL
    )
    AND e.status IN ('draft', 'completed')
  ORDER BY e.updated_at DESC
  LIMIT 25;
$function$;

REVOKE ALL ON FUNCTION public.get_encounter_workflow_workspace() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_encounter_workflow_workspace() TO authenticated;

NOTIFY pgrst, 'reload schema';
