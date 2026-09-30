# Public SECURITY DEFINER exposure contract

This contract protects the exposed public schema from accidental SECURITY DEFINER RPC exposure.

For every public SECURITY DEFINER function found in migration history, the repository requires:

- an explicit search_path;
- an explicit EXECUTE revoke in migration history so PostgreSQL's PUBLIC default is not relied upon;
- no migration grant of EXECUTE to PUBLIC;
- no migration grant of EXECUTE to anon.

The contract is separate from function-specific authorization review. It does not decide whether authenticated EXECUTE is appropriate; that remains governed by the high-risk authorization and function-privilege contracts.

This is source-level protection. The live PostgreSQL catalog audit remains the authoritative verification of effective production privileges.

Run:

`npm run test:public-security-definer-exposure`
