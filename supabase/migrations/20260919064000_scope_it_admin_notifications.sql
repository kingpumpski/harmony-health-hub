CREATE OR REPLACE FUNCTION public.get_workflow_notifications(_limit integer DEFAULT 100)
RETURNS TABLE(
  id uuid,
  recipient_role text,
  recipient_user_id uuid,
  title text,
  message text,
  severity text,
  category text,
  link text,
  related_patient_id uuid,
  related_entity_id uuid,
  metadata jsonb,
  is_read boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $function$
DECLARE
  lim integer := least(greatest(coalesce(_limit, 50), 1), 500);
  is_it_admin boolean := public.has_role(auth.uid(), 'it_admin'::public.app_role);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  RETURN QUERY
  SELECT
    n.id,
    n.recipient_role::text,
    n.recipient_user_id,
    n.title,
    CASE WHEN is_it_admin THEN regexp_replace(coalesce(n.message, ''), '[[:space:]]+', ' ', 'g') ELSE n.message END,
    n.severity::text,
    n.category::text,
    CASE WHEN is_it_admin THEN NULL::text ELSE n.link END,
    CASE WHEN is_it_admin THEN NULL::uuid ELSE n.related_patient_id END,
    CASE WHEN is_it_admin THEN NULL::uuid ELSE n.related_entity_id END,
    CASE WHEN is_it_admin THEN NULL::jsonb ELSE n.metadata END,
    n.is_read,
    n.created_at
  FROM public.notifications n
  WHERE
    (
      n.recipient_user_id = auth.uid()
      OR (
        n.recipient_role IS NOT NULL
        AND public.has_role(auth.uid(), n.recipient_role::public.app_role)
      )
    )
    AND (
      NOT is_it_admin
      OR (
        n.recipient_role = 'it_admin'
        AND n.category = 'it_support'
      )
    )
  ORDER BY n.created_at DESC
  LIMIT lim;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_workflow_notifications(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_workflow_notifications(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_workflow_notifications(integer) TO authenticated;
NOTIFY pgrst, 'reload schema';