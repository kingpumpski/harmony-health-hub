CREATE OR REPLACE FUNCTION public.get_encounter_workflow_workspace()
RETURNS TABLE(
  encounter_id UUID, patient_id UUID, patient_name TEXT, patient_code TEXT,
  status TEXT, version_no INTEGER, admission_id UUID, created_at TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=public AS $$
  SELECT e.id,e.patient_id,concat(p.first_name,' ',p.last_name),p.patient_code,
         e.status,e.version_no,e.admission_id,e.created_at
  FROM public.encounters e
  JOIN public.patients p ON p.id=e.patient_id
  WHERE (e.practitioner_id=auth.uid() OR public.has_role(auth.uid(),'admin'))
    AND e.status IN ('draft','completed')
  ORDER BY e.updated_at DESC
  LIMIT 25;
$$;
REVOKE ALL ON FUNCTION public.get_encounter_workflow_workspace() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_encounter_workflow_workspace() TO authenticated;
