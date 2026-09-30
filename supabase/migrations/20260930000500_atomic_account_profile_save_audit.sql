BEGIN;

CREATE OR REPLACE FUNCTION public.save_my_profile(
  _first_name text,
  _last_name text,
  _phone text DEFAULT NULL,
  _department text DEFAULT NULL,
  _specialization text DEFAULT NULL
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_user uuid := (select auth.uid());
  v_previous jsonb;
  v_next jsonb;
  v_profile public.profiles;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT to_jsonb(p) INTO v_previous
  FROM public.profiles p
  WHERE p.id = v_user
  FOR UPDATE;

  IF v_previous IS NULL THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  UPDATE public.profiles
  SET first_name = btrim(_first_name),
      last_name = btrim(_last_name),
      phone = nullif(btrim(_phone), ''),
      department = nullif(btrim(_department), ''),
      specialization = nullif(btrim(_specialization), ''),
      updated_at = now()
  WHERE id = v_user
  RETURNING * INTO v_profile;

  v_next := to_jsonb(v_profile);

  PERFORM public.record_system_audit(
    'user_update_profile',
    'account',
    'user',
    v_user,
    'info',
    jsonb_build_object('previous_profile', v_previous, 'next_profile', v_next)
  );

  RETURN v_profile;
END;
$$;

REVOKE ALL ON FUNCTION public.save_my_profile(text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_my_profile(text,text,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.save_my_profile(text,text,text,text,text) TO authenticated;

COMMIT;
