-- Scope IT support audit-log reads through a server-side role-gated RPC.
CREATE OR REPLACE FUNCTION public.get_it_support_system_logs(
  _module text DEFAULT NULL,
  _severity text DEFAULT NULL,
  _limit integer DEFAULT 250
)
RETURNS TABLE(
  id uuid,
  action text,
  module text,
  entity_type text,
  severity text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'it_admin')
  ) THEN
    RAISE EXCEPTION 'IT support log access required';
  END IF;

  RETURN QUERY
  SELECT l.id, l.action, l.module, l.entity_type, l.severity, l.created_at
  FROM public.system_audit_log l
  WHERE (_module IS NULL OR _module = '' OR l.module = _module)
    AND (_severity IS NULL OR _severity = '' OR l.severity = _severity)
  ORDER BY l.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(_limit,250),500));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_it_support_system_logs(text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_it_support_system_logs(text,text,integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
