-- Staff shift assignments are operational security data. Keep writes server-authoritative.

CREATE OR REPLACE FUNCTION public.create_staff_shift_assignment(
  _user_id UUID,
  _department TEXT,
  _shift_label TEXT,
  _starts_at TIMESTAMPTZ,
  _ends_at TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE assignment_id UUID;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Shift management access denied';
  END IF;
  IF _user_id IS NULL OR NULLIF(trim(_department), '') IS NULL OR NULLIF(trim(_shift_label), '') IS NULL THEN
    RAISE EXCEPTION 'Staff, department and shift label are required';
  END IF;
  IF _starts_at IS NULL OR _ends_at IS NULL OR _ends_at <= _starts_at THEN
    RAISE EXCEPTION 'Shift end must be after shift start';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = _user_id) THEN
    RAISE EXCEPTION 'Staff profile not found';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM public.staff_shift_assignments s
    WHERE s.user_id = _user_id
      AND s.department = _department
      AND s.active
      AND tstzrange(s.starts_at, s.ends_at, '[)') && tstzrange(_starts_at, _ends_at, '[)')
  ) THEN
    RAISE EXCEPTION 'Staff member already has an overlapping active shift in this department';
  END IF;
  INSERT INTO public.staff_shift_assignments(user_id, department, shift_label, starts_at, ends_at, active)
  VALUES(_user_id, trim(_department), trim(_shift_label), _starts_at, _ends_at, true)
  RETURNING id INTO assignment_id;
  RETURN assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_staff_shift_assignment_active(
  _assignment_id UUID,
  _active BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Shift management access denied';
  END IF;
  UPDATE public.staff_shift_assignments
  SET active = _active
  WHERE id = _assignment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Shift assignment not found';
  END IF;
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.create_staff_shift_assignment(UUID,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_staff_shift_assignment_active(UUID,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_staff_shift_assignment(UUID,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_staff_shift_assignment_active(UUID,BOOLEAN) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.staff_shift_assignments FROM authenticated;
