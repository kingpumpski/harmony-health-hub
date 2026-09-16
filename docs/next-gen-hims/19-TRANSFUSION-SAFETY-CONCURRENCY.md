# Transfusion Safety / Concurrency Hardening

The existing transfusion lifecycle remains the canonical workflow. This pass strengthens it without introducing another blood-bank service.

Controls added at the database boundary:

- transfusion row locking before lifecycle changes;
- monotonic state transitions: issued → running → completed/stopped, with cancellation before running;
- terminal-state protection and idempotent same-terminal responses;
- consent remains confirmed for active/completed transfusion states;
- blood-unit identifier required before running;
- reaction documentation required whenever a reaction is recorded;
- linked closed encounters cannot be advanced;
- reaction and lifecycle events are audited;
- direct authenticated mutation remains revoked.

Verification is represented by `scripts/test-nextgen-transfusion-safety.mjs` and is intended to run with the existing next-generation quality gates.

Live migration replay and concurrency execution remain pending until the active Harmony Supabase project is available through the connected Supabase environment.
