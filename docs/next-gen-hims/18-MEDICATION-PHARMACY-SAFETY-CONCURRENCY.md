# Medication and Pharmacy Safety / Concurrency Hardening

## Scope

This pass hardens the existing medication-administration and pharmacy workflows on the next-generation HIMS reference branch. It does not create a parallel medication or pharmacy service.

## Medication administration

The existing `medication_administrations` table and lifecycle RPC remain the canonical workflow. Direct authenticated INSERT/UPDATE/DELETE remains revoked.

The server boundary now additionally enforces:

- row locking before medication state transition;
- explicit allowed terminal states;
- clinical reason for held, refused, and omitted medication;
- actor and administration timestamp for administered medication;
- no self-witnessing;
- witness must be an authorized clinical user;
- scheduled medication cannot retain an administration actor;
- administration cannot occur outside the configured due window;
- closed records cannot be transitioned again;
- reopen requires an explicit professional reason;
- reopening clears prior administration attribution before returning the record to scheduled state;
- system audit for administration-state transitions and reopen actions.

A database trigger provides a final integrity boundary so invalid medication state combinations fail even if a future server workflow is introduced.

## Pharmacy dispensing

The existing server-authoritative pharmacy lifecycle is retained. The confirmation path now additionally provides:

- row locking on the dispensing plan, service order, and inventory item;
- payment/release gate enforcement;
- closed-encounter protection;
- conditional stock decrement to prevent concurrent oversell/race conditions;
- conditional plan transition so only one transaction can commit dispensing;
- idempotent response when the plan is already dispensed;
- non-negative inventory guard;
- canonical system audit for completed dispensing;
- continued authenticated direct-write lockdown for dispensing plans, POS sales, and inventory.

## Verification contract

`scripts/test-nextgen-medication-pharmacy-safety.mjs` checks the source-level security and concurrency contract, including preservation of the existing workflow foundations and the new hardening boundary.

A successful contract test is necessary but not sufficient for production certification. Live migration replay, RLS verification, concurrency execution, clinical safety validation, and exact-head CI/deployment evidence remain required before promotion.

## External verification blocker

The active Harmony Supabase project is not currently available through the connected Supabase project list. Therefore this pass does not claim live migration execution. The existing Vercel rate-limit failure likewise remains an infrastructure blocker and is not treated as a code-quality result.
