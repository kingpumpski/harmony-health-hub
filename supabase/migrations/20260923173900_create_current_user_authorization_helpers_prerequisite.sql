-- Create current-user-only authorization helpers before the RLS and RPC
-- reconciliation migrations that reference them. These wrappers accept no
-- arbitrary user ID and therefore expose only the caller's own role context.
CREATE OR REPLACE FUNCTION public.current_user_has_role(_role public.app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $current_user_has_role$
  SELECT public.has_role((SELECT auth.uid()), _role);
$current_user_has_role$;

CREATE OR REPLACE FUNCTION public.current_user_is_clinical_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $current_user_is_clinical_staff$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (
       SELECT 1
       FROM public.user_roles
       WHERE user_id = (SELECT auth.uid())
         AND role IN (
           'admin','practitioner','nurse','midwife','specialist_nurse',
           'lab_technician','radiologist','pharmacist','accountant',
           'front_desk','canteen'
         )
     );
$current_user_is_clinical_staff$;

CREATE OR REPLACE FUNCTION public.current_user_can_edit_patient_record()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $current_user_can_edit_patient_record$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (
       SELECT 1
       FROM public.user_roles
       WHERE user_id = (SELECT auth.uid())
         AND role IN ('admin','practitioner','nurse','midwife','front_desk')
     );
$current_user_can_edit_patient_record$;


CREATE OR REPLACE FUNCTION public.current_user_has_facility_access(_facility_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $current_user_has_facility_access$
  SELECT public.has_facility_access((SELECT auth.uid()), _facility_id);
$current_user_has_facility_access$;

REVOKE ALL ON FUNCTION public.current_user_has_facility_access(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_facility_access(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_user_has_role(public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_role(public.app_role) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_user_is_clinical_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_is_clinical_staff() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_user_can_edit_patient_record() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_can_edit_patient_record() TO authenticated, service_role;
