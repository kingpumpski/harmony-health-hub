-- Gate A: protected encounter list for the operational workspace.
CREATE OR REPLACE FUNCTION public.get_encounter_worklist(_limit integer DEFAULT 50)
RETURNS TABLE(
  id uuid, patient_id uuid, symptoms text, clerking_notes text,
  principal_diagnosis text, treatment_plan text, encounter_type text,
  status text, admission_id uuid, created_at timestamptz,
  updated_at timestamptz, practitioner_id uuid, submitted_at timestamptz,
  version_no integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
  SELECT e.id,e.patient_id,e.symptoms,e.clerking_notes,e.principal_diagnosis,
         e.treatment_plan,e.encounter_type,e.status,e.admission_id,e.created_at,
         e.updated_at,e.practitioner_id,e.submitted_at,e.version_no
  FROM public.encounters e
  JOIN public.patients p ON p.id=e.patient_id
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
    AND e.status IN ('draft','completed')
  ORDER BY e.updated_at DESC
  LIMIT LEAST(GREATEST(COALESCE(_limit,50),1),200);
$function$;
REVOKE ALL ON FUNCTION public.get_encounter_worklist(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_encounter_worklist(integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
