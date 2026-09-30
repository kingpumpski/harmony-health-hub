# Secure-by-default function execution

Supabase/Postgres functions are executable by default unless execution privileges are restricted. The project already has explicit execution hardening for many RPCs; this adds a **future-function default deny** so a newly created public function cannot accidentally become callable through the Data API.

The migration revokes default function execution for the `postgres` owner in the exposed `public` schema from:

- `PUBLIC`
- `anon`
- `authenticated`

Application RPC migrations must explicitly grant execution to the role(s) that require them.

This does **not** revoke execution from existing functions. Existing functions remain governed by their individual authorization review and explicit privilege state.

The migration is committed to the authorization hardening branch and is **not applied to production** by this change. It must first be validated in an isolated Supabase environment because default-privilege changes affect future database functions.

Run:

`npm run test:default-function-execute`
