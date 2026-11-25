BEGIN;

SELECT plan(2);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_default_acl d
    JOIN pg_namespace n ON n.oid = d.defaclnamespace
    CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
    WHERE d.defaclrole = 'postgres'::regrole
      AND n.nspname = 'public'
      AND d.defaclobjtype = 'f'
      AND acl.privilege_type = 'EXECUTE'
      AND (acl.grantee = 0 OR acl.grantee IN ('anon'::regrole, 'authenticated'::regrole))
  ),
  'postgres-created public functions do not inherit EXECUTE for PUBLIC, anon, or authenticated'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM pg_default_acl d
    JOIN pg_namespace n ON n.oid = d.defaclnamespace
    CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
    WHERE d.defaclrole = 'supabase_admin'::regrole
      AND n.nspname = 'public'
      AND d.defaclobjtype = 'f'
      AND acl.privilege_type = 'EXECUTE'
      AND (acl.grantee = 0 OR acl.grantee IN ('anon'::regrole, 'authenticated'::regrole))
  ),
  'supabase_admin-created public functions do not inherit EXECUTE for PUBLIC, anon, or authenticated'
);

SELECT * FROM finish();
ROLLBACK;
