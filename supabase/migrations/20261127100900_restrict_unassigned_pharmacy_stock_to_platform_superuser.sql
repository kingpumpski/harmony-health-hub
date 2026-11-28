-- Unassigned pharmacy stock has no trustworthy facility lineage.
-- Only the platform superuser may inspect or assign this global reconciliation queue.
DO $migration$
DECLARE
  v_workspace text;
  v_assign text;
  v_workspace_marker text := 'CASE WHEN v_admin OR v_superuser THEN COALESCE((';
  v_assign_marker text := 'IF uid IS NULL OR NOT (public.has_role(uid, ''admin'') OR public.has_role(uid, ''system_superuser'')) THEN';
  v_count integer;
  v_workspace_definer boolean;
  v_workspace_empty_path boolean;
  v_assign_definer boolean;
  v_assign_empty_path boolean;
BEGIN
  SELECT pg_catalog.pg_get_functiondef(p.oid), p.prosecdef,
         COALESCE(p.proconfig @> ARRAY['search_path=""'], false)
    INTO v_workspace, v_workspace_definer, v_workspace_empty_path
  FROM pg_catalog.pg_proc p
  WHERE p.oid = 'public.get_pharmacy_workspace(integer)'::pg_catalog.regprocedure;

  IF v_workspace IS NULL OR NOT v_workspace_definer OR NOT v_workspace_empty_path THEN
    RAISE EXCEPTION 'Pharmacy workspace RPC is missing or no longer SECURITY DEFINER';
  END IF;

  v_count := (pg_catalog.length(v_workspace) - pg_catalog.length(pg_catalog.replace(v_workspace, v_workspace_marker, ''))) / pg_catalog.length(v_workspace_marker);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one unassigned-stock visibility gate in pharmacy workspace; found %', v_count;
  END IF;
  v_workspace := pg_catalog.replace(v_workspace, v_workspace_marker, 'CASE WHEN v_superuser THEN COALESCE((');

  SELECT pg_catalog.pg_get_functiondef(p.oid), p.prosecdef,
         COALESCE(p.proconfig @> ARRAY['search_path=""'], false)
    INTO v_assign, v_assign_definer, v_assign_empty_path
  FROM pg_catalog.pg_proc p
  WHERE p.oid = 'public.assign_unattributed_pharmacy_inventory(uuid,text)'::pg_catalog.regprocedure;

  IF v_assign IS NULL OR NOT v_assign_definer OR NOT v_assign_empty_path THEN
    RAISE EXCEPTION 'Unassigned inventory reconciliation RPC is missing or no longer SECURITY DEFINER';
  END IF;

  v_count := (pg_catalog.length(v_assign) - pg_catalog.length(pg_catalog.replace(v_assign, v_assign_marker, ''))) / pg_catalog.length(v_assign_marker);
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one facility-admin assignment gate for unassigned stock; found %', v_count;
  END IF;
  v_assign := pg_catalog.replace(
    v_assign,
    v_assign_marker,
    'IF uid IS NULL OR NOT public.has_role(uid, ''system_superuser'') THEN'
  );

  EXECUTE v_workspace;
  EXECUTE v_assign;
END;
$migration$;

REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_unattributed_pharmacy_inventory(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_unattributed_pharmacy_inventory(uuid,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
