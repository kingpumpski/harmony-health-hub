-- Harden inpatient SECURITY DEFINER search-path configuration without rewriting the
-- already-authorized workflow bodies. PostgreSQL supports function-local configuration
-- through ALTER FUNCTION; an empty search_path prevents unqualified non-system object
-- resolution from inheriting caller-controlled schemas.

ALTER FUNCTION public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text)
  SET search_path = '';

ALTER FUNCTION public.create_admission_workflow(uuid,text,text,text)
  SET search_path = '';

REVOKE ALL ON FUNCTION public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_admission_workflow(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(uuid,text,text,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
