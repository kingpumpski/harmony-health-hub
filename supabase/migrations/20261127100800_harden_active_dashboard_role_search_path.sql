-- Harden the dynamically-derived active-role dashboard RPC without changing its behavior.
DO $migration$
DECLARE
  v_function regprocedure;
  v_definition text;
  v_is_security_definer boolean;
  v_return_type oid;
BEGIN
  v_function := pg_catalog.to_regprocedure('public.get_role_dashboard_summary_for_role(text)');
  IF v_function IS NULL THEN
    RAISE EXCEPTION 'Required active-role dashboard RPC is missing; replay the canonical dashboard migrations first';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(v_function),
         p.prosecdef,
         p.prorettype
    INTO v_definition, v_is_security_definer, v_return_type
  FROM pg_catalog.pg_proc p
  WHERE p.oid = v_function;

  IF v_definition IS NULL
     OR v_is_security_definer
     OR v_return_type <> 'jsonb'::pg_catalog.regtype
     OR pg_catalog.position('Requested dashboard role is not assigned to the authenticated user' IN v_definition) = 0
     OR pg_catalog.position('ur.role::text = _requested_role' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Active-role dashboard RPC does not match the reviewed SECURITY INVOKER authorization contract';
  END IF;
END;
$migration$;

ALTER FUNCTION public.get_role_dashboard_summary_for_role(text)
  SET search_path TO pg_catalog, public;

REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
