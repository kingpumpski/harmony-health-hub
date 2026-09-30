-- Read-only production audit for public SECURITY DEFINER function execution.
-- Run only with a read-capable database role. This script performs no writes.

SELECT n.nspname AS schema_name, p.proname AS function_name, pg_get_function_identity_arguments(p.oid) AS identity_arguments, p.prosecdef AS security_definer, COALESCE(p.proconfig, ARRAY[]::text[]) AS configuration, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute, has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute, p.proacl AS access_control_list
FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef=true ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

SELECT n.nspname AS schema_name, p.proname AS function_name, pg_get_function_identity_arguments(p.oid) AS identity_arguments
FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef=true AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

SELECT n.nspname AS schema_name, p.proname AS function_name, pg_get_function_identity_arguments(p.oid) AS identity_arguments
FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef=true AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS cfg WHERE cfg LIKE 'search_path=%')
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);
