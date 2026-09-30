# Live Function Privilege Audit

`scripts/live-function-privilege-audit.sql` is a read-only PostgreSQL catalog audit for public SECURITY DEFINER functions.

It records function identity, arguments, SECURITY DEFINER status, configured settings, effective anon/authenticated EXECUTE privileges, and the current PostgreSQL ACL.

It also produces focused exception sets for anonymous execution and missing explicit search_path.

This is deliberately separate from source-level privilege contracts: source contracts verify intended migration history, while the catalog audit verifies effective database privilege state.

The audit performs no writes and does not replace isolated authorization regression testing.
