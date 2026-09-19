-- Governed user-role assignment boundary.
-- The existing app_role enum and user_roles table remain canonical. This RPC
-- prevents the UI from performing direct privileged role-table DML.

CREATE OR REPLACE FUNCTION public.set_hms_user_role(_target_user_id uuid, _role text)
RETURNS public.user_roles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result_row public.user_roles;
  target_is_admin boolean;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Administrator authorization required' USING ERRCODE = '42501';
  END IF;

  IF _target_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = _target_user_id) THEN
    RAISE EXCEPTION 'Target user does not exist';
  END IF;

  IF _role IS NULL OR _role NOT IN (
    'admin','practitioner','nurse','midwife','lab_technician',
    'pharmacist','accountant','front_desk','canteen','patient'
  ) THEN
    RAISE EXCEPTION 'Unsupported HMS application role';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _target_user_id AND role = 'admin'::public.app_role
  ) INTO target_is_admin;

  IF target_is_admin AND _role <> 'admin'
     AND (SELECT count(*) FROM public.user_roles WHERE role = 'admin'::public.app_role) <= 1 THEN
    RAISE EXCEPTION 'The final administrator cannot be demoted';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = _target_user_id;
  INSERT INTO public.user_roles(user_id, role)
  VALUES (_target_user_id, _role::public.app_role)
  RETURNING * INTO result_row;

  RETURN result_row;
END;
$$;

REVOKE ALL ON FUNCTION public.set_hms_user_role(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_hms_user_role(uuid,text) TO authenticated;

COMMENT ON FUNCTION public.set_hms_user_role(uuid,text)
IS 'Canonical administrator-controlled role assignment. Preserves the existing app_role/user_roles authority and prevents removal of the final administrator.';
