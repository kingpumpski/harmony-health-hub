BEGIN;

SELECT plan(3);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) acl
    WHERE n.nspname='public'
      AND c.relname IN ('lab_test_groups','lab_test_group_items')
      AND acl.grantee IN (0, 'anon'::regrole, 'authenticated'::regrole)
  ),
  'laboratory panel tables grant no direct table privileges to PUBLIC, anon or authenticated'
);

SELECT ok(
  (SELECT count(*) FROM pg_class c
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public'
     AND c.relname IN ('lab_test_groups','lab_test_group_items')
     AND c.relrowsecurity) = 2,
  'both laboratory panel tables retain row-level security'
);

SELECT ok(
  (SELECT count(*) FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND (
       (p.proname='get_laboratory_test_groups'
        AND pg_get_function_identity_arguments(p.oid)='_include_inactive boolean')
       OR
       (p.proname='save_laboratory_test_group'
        AND pg_get_function_identity_arguments(p.oid)='_group_id uuid, _group_name text, _group_code text, _description text, _default_charge numeric, _test_ids uuid[], _is_active boolean DEFAULT true')
     )
     AND p.prosecdef
     AND COALESCE(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
     AND has_function_privilege('authenticated',p.oid,'EXECUTE')
     AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) = 2,
  'laboratory panel RPCs remain authenticated-only SECURITY DEFINER functions with pinned search paths'
);

SELECT * FROM finish();
ROLLBACK;
