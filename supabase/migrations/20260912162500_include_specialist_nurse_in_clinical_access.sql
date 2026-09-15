CREATE OR REPLACE FUNCTION public.is_clinical_staff(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role IN (
        'admin','practitioner','nurse','specialist_nurse','midwife',
        'lab_technician','pharmacist','front_desk'
      )
  )
$$;
