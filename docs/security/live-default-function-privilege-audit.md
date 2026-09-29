# Live Default Function Privilege Audit

This read-only PostgreSQL catalog audit inspects `pg_default_acl` to show which roles have default privileges for newly created functions.

The audit is important because `ALTER DEFAULT PRIVILEGES FOR ROLE postgres` only affects functions created by `postgres`. If another role creates application functions, that role needs an equivalent audited default-privilege policy.

The audit performs no writes and does not change existing function ACLs.
