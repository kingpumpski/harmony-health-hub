# Database compatibility repair — October 19, 2026

## Verified repairs

- Migration workflow choice options now belong to the mode input, not the text confirmation input.
- Migration execution now rejects duplicate versions before linking or applying changes.
- Laboratory missing-object database tests now check panel and membership column types, required facility scope, order panel links, and sample quantity types.
- Dental no longer evaluates a refresh control outside its component; missing icons are imported.
- Department and emergency refresh controls now use declared loading state.
- Header labels include all four specialist roles previously absent from its map.
- Both notification functions using Nodemailer now enable Deno automatic npm dependency resolution; importing the pinned email dependency succeeded.

## Verification

Passed: migration workflow safety, migration concurrency, laboratory attachment schema, React hook imports, edge schema/role inventory, role dashboards, and project integrity repository tests.

The public login page rendered at `/login` without browser page errors. This is not verification of authenticated clinical workflows.

## Blocking conditions

Three read-only database schema requests failed because the Cloud database connection pooler was unavailable. Database health metrics were also unavailable. No deployed schema, migration ledger, or account roles were changed, and generated types were not refreshed from an unavailable schema.

The migration uniqueness test fails: 21 versions are shared by multiple files. Do not renumber these blindly: first compare each filename and SQL with the deployed ledger, preserve applied identities, and allocate unique versions only to confirmed unapplied entries. Never execute the whole historical chain without that reconciliation.

Existing generated types list only a small subset of the functions expected by the application. The latest preview build report still contains schema-related compilation errors. This repair does not establish an error-free build or deployed database.

## Next checks when Cloud is available

1. Read the deployed migration ledger and public schema; confirm the October 15 laboratory and payroll repairs are present.
2. Reconcile conflicting migration versions with recorded history before applying any missing SQL through the managed migration tool.
3. Apply existing repair migration SQL byte-for-byte where needed; retain legacy metadata validation and authorization safeguards.
4. Refresh generated types from the verified live schema and address remaining compilation errors without adding suppression directives.
5. Run the laboratory missing-object database contract and the operational/security database contracts.
6. Verify patient, laboratory, pharmacy, billing, and emergency workflows using an authenticated session.