# Offline Replay Security Contract

Offline mutations persist an idempotency key so replay is deterministic and safe against duplicate submission. The replay path may refresh the session credential, but it must never reuse a persisted Authorization header when the current session has no access token.

Required invariant:

- Preserve the persisted `x-harmony-idempotency-key` for the lifetime of a queued mutation.
- Before replay, remove any persisted `authorization` header.
- If the current authenticated session supplies an access token, send only that refreshed Bearer token.
- If no current access token exists, replay must not send a stale credential.
- Permanent HTTP failures remain blocked for manual resolution.
- Transient failures remain pending with bounded exponential backoff.

This contract is intentionally separate from the database authorization model. Offline replay must never broaden server authorization or convert a protected clinical/financial workflow into an offline-capable operation without an explicit server-side contract.
