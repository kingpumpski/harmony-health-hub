-- Allow authorized laboratory staff to resolve the signing signature of the approved report actor.
CREATE OR REPLACE FUNCTION public.get_staff_signature_for_report(_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path='public'
AS $function$
  SELECT ss.signature_data
  FROM public.staff_signatures ss
  WHERE ss.user_id=_user_id
    AND ss.facility_id IS NOT DISTINCT FROM public.current_user_facility_id()
  ORDER BY ss.updated_at DESC
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_staff_signature_for_report(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_staff_signature_for_report(uuid) TO authenticated;
