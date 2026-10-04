BEGIN;

DROP FUNCTION IF EXISTS public.create_ward_unit(text,text,text,text);

CREATE FUNCTION public.create_ward_unit(
  _name text,
  _code text,
  _specialty text,
  _gender_policy text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  RETURN public.create_ward_unit(
    _name,
    _code,
    _specialty,
    _gender_policy,
    public.current_user_facility_id()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.create_ward_unit(text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_ward_unit(text,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_ward_unit(text,text,text,text) TO authenticated;

COMMIT;