-- Read-only audit of PostgreSQL default function privileges.
-- This verifies which function-creating roles have explicit default ACL entries.

SELECT
  r.rolname AS owner_role,
  n.nspname AS schema_name,
  d.defaclobjtype AS object_type,
  d.defaclacl AS default_acl
FROM pg_default_acl AS d
JOIN pg_roles AS r ON r.oid=d.defaclrole
LEFT JOIN pg_namespace AS n ON n.oid=d.defaclnamespace
WHERE d.defaclobjtype='f'
ORDER BY r.rolname, n.nspname;

-- Focused audit for postgres-created public functions.
SELECT
  r.rolname AS owner_role,
  COALESCE(n.nspname,'') AS schema_name,
  d.defaclacl AS default_acl
FROM pg_default_acl AS d
JOIN pg_roles AS r ON r.oid=d.defaclrole
LEFT JOIN pg_namespace AS n ON n.oid=d.defaclnamespace
WHERE d.defaclobjtype='f'
  AND r.rolname='postgres'
  AND COALESCE(n.nspname,'')='public';

-- The secure-default migration is intentionally scoped to functions created
-- by postgres; other function owners require equivalent audited defaults.
