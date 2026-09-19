-- Reconcile the broader role catalogue with the existing user_roles authority.
-- hms_role_catalog is a permission-policy catalogue, not a second identity/RBAC source.

CREATE OR REPLACE FUNCTION public.hms_current_role_code(_user_id uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public AS $$
  SELECT CASE
    WHEN public.has_role(_user_id,'admin'::public.app_role) THEN 'super_admin'
    WHEN public.has_role(_user_id,'practitioner'::public.app_role) THEN 'doctor'
    WHEN public.has_role(_user_id,'specialist_nurse'::public.app_role) THEN 'nurse'
    WHEN public.has_role(_user_id,'lab_technician'::public.app_role) THEN 'lab_scientist'
    WHEN public.has_role(_user_id,'accountant'::public.app_role) THEN 'billing_clerk'
    WHEN public.has_role(_user_id,'front_desk'::public.app_role) THEN 'receptionist'
    WHEN public.has_role(_user_id,'pharmacist'::public.app_role) THEN 'pharmacist'
    WHEN public.has_role(_user_id,'radiologist'::public.app_role) THEN 'radiologist'
    WHEN public.has_role(_user_id,'midwife'::public.app_role) THEN 'midwife'
    WHEN public.has_role(_user_id,'patient'::public.app_role) THEN 'patient'
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.hms_has_module_permission(
  _module_code text, _action text, _user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public AS $$
  SELECT CASE
    WHEN public.has_role(_user_id,'admin'::public.app_role) THEN true
    ELSE COALESCE((
      SELECT CASE lower(_action)
        WHEN 'read' THEN p.can_read
        WHEN 'write' THEN p.can_write
        WHEN 'approve' THEN p.can_approve
        WHEN 'configure' THEN p.can_configure
        ELSE false
      END
      FROM public.hms_role_module_permissions p
      WHERE p.role_code = public.hms_current_role_code(_user_id)
        AND p.module_code = _module_code
    ),false)
  END;
$$;

REVOKE ALL ON FUNCTION public.hms_has_module_permission(text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.hms_has_module_permission(text,text,uuid) TO authenticated;

-- Replace the placeholder all-false matrix with explicit least-privilege defaults.
INSERT INTO public.hms_role_module_permissions(role_code,module_code,can_read,can_write,can_approve,can_configure,scope_code)
SELECT r.role_code, m.module_code,
       CASE
         WHEN r.role_code IN ('doctor','specialist','surgeon','nurse','midwife','pharmacist','lab_scientist','radiologist','physiotherapist','fertility_specialist','dietitian','anesthetist','triage_officer','ward_clerk') AND m.module_code IN ('M1','M2','M3','M7','M8','M9','M10','M11','M12','M15','M16','M17') THEN true
         WHEN r.role_code IN ('receptionist','admissions_officer','records_officer','cashier','billing_clerk','insurance_officer') AND m.module_code IN ('M1','M2','M14','M15','M16','M17') THEN true
         WHEN r.role_code IN ('report_centre_manager','statutory_officer','bi_analyst','departmental_viewer') AND m.module_code='M16' THEN true
         WHEN r.role_code IN ('biomedical_engineer') AND m.module_code='M24' THEN true
         WHEN r.role_code IN ('restaurant_manager','chef','order_clerk','attendant','dietitian') AND m.module_code='M13' THEN true
         WHEN r.role_code IN ('lecturer','student','supervisor','researcher') AND m.module_code='M21' THEN true
         WHEN r.role_code IN ('facility_module_manager') AND m.module_code='M25' THEN true
         ELSE false
       END,
       CASE
         WHEN r.role_code IN ('doctor','specialist','surgeon','nurse','midwife','pharmacist','lab_scientist','radiologist','physiotherapist','fertility_specialist','dietitian','anesthetist','triage_officer','ward_clerk') AND m.module_code IN ('M3','M7','M8','M9','M10','M11','M12','M15') THEN true
         WHEN r.role_code IN ('receptionist','admissions_officer','records_officer','cashier','billing_clerk','insurance_officer') AND m.module_code IN ('M1','M2','M14','M15') THEN true
         WHEN r.role_code IN ('restaurant_manager','chef','order_clerk','attendant') AND m.module_code='M13' THEN true
         WHEN r.role_code='biomedical_engineer' AND m.module_code='M24' THEN true
         ELSE false
       END,
       CASE
         WHEN r.role_code IN ('medical_director','hospital_admin','compliance','report_centre_manager','statutory_officer') THEN true
         ELSE false
       END,
       CASE WHEN r.role_code IN ('hospital_admin','facility_module_manager') THEN true ELSE false END,
       CASE WHEN r.role_code IN ('departmental_viewer','bi_analyst') THEN 'department' ELSE 'facility' END
FROM public.hms_role_catalog r
CROSS JOIN (VALUES
 ('M1'),('M2'),('M3'),('M4'),('M5'),('M6'),('M7'),('M8'),('M9'),('M10'),('M11'),('M12'),('M13'),('M14'),('M15'),('M16'),('M17'),('M18'),('M19'),('M20'),('M21'),('M22'),('M23'),('M24'),('M25')
) AS m(module_code)
ON CONFLICT(role_code,module_code) DO UPDATE SET
 can_read=EXCLUDED.can_read, can_write=EXCLUDED.can_write,
 can_approve=EXCLUDED.can_approve, can_configure=EXCLUDED.can_configure,
 scope_code=EXCLUDED.scope_code;

-- Correct the broader module-code mismatches without creating duplicate modules.
UPDATE public.hms_role_module_permissions
SET module_code='M23'
WHERE module_code='M23-P';

-- Protect the policy catalogue itself; application permissions are evaluated through
-- hms_has_module_permission and the existing user_roles authority.
DROP POLICY IF EXISTS hms_role_catalog_admin ON public.hms_role_catalog;
CREATE POLICY hms_role_catalog_admin ON public.hms_role_catalog
FOR SELECT TO authenticated USING (
  public.has_role(auth.uid(),'admin'::public.app_role)
  OR public.hms_has_module_permission('M19','read')
);
CREATE POLICY hms_role_catalog_configure ON public.hms_role_catalog
FOR UPDATE TO authenticated USING (
  public.has_role(auth.uid(),'admin'::public.app_role)
) WITH CHECK (
  public.has_role(auth.uid(),'admin'::public.app_role)
);

DROP POLICY IF EXISTS hms_role_matrix_admin ON public.hms_role_module_permissions;
CREATE POLICY hms_role_matrix_read ON public.hms_role_module_permissions
FOR SELECT TO authenticated USING (
  public.has_role(auth.uid(),'admin'::public.app_role)
  OR public.hms_has_module_permission('M19','read')
);
CREATE POLICY hms_role_matrix_configure ON public.hms_role_module_permissions
FOR ALL TO authenticated USING (
  public.has_role(auth.uid(),'admin'::public.app_role)
  OR public.hms_has_module_permission('M19','configure')
) WITH CHECK (
  public.has_role(auth.uid(),'admin'::public.app_role)
  OR public.hms_has_module_permission('M19','configure')
);

COMMENT ON FUNCTION public.hms_has_module_permission(text,text,uuid)
IS 'Canonical permission bridge: existing user_roles remains the identity authority; broader HMS role catalogue supplies least-privilege module actions.';
