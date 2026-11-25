# Migration collision review: 20260912010000

Updated: 2026-11-25

## Scope

Compared the two repository candidates sharing migration version `20260912010000` with the live canonical PostgreSQL catalog. This is a provenance and interaction review, not authorization to rename, delete, replay, or apply either candidate.

Candidates:
- `20260912010000_phase6_anesthetic_assessment_foundation.sql`
- `20260912010000_phase8_ai_clinical_provenance.sql`

## Decision

**Do not select one candidate as the winner. Both represent distinct feature tracks and both corresponding feature families exist in the live database.** Their same 14-digit version is a migration-history collision, not proof that one is redundant. Preserve both original SQL files and continue the per-group reconciliation process.

## Live catalog evidence

Read-only inspection of the canonical project confirmed:
- `anesthetic_assessments`, `ai_clinical_sessions`, and `ai_clinical_events` all exist.
- All three tables have RLS enabled (from the previously captured full-schema inventory).
- The live tables have evolved beyond the candidates. For example, anesthetic assessments include `encounter_id`, `questionnaire`, and `facility_id`; AI sessions include `facility_id`.
- Live anesthetic policies include patient-self read, staff insert/update/delete, and restrictive facility identity policies. A live `enforce_remaining_facility_lineage` trigger supplies and validates facility attribution.
- Live AI session policies include role/creator read access plus restrictive facility-access and facility-identity SELECT guards. A facility-lineage trigger validates session writes.
- Live AI event reads are role-scoped. An insert/update trigger validates that the event's session has facility attribution and that a non-privileged actor's active facility matches it.
- Live AI event `actor_id` is NOT NULL while its FK uses `ON DELETE SET NULL`. These two rules conflict on auth-user deletion: the FK action attempts to null a non-nullable column, so deletion of a referenced auth user can fail. This should be resolved in a separate, forward-only repair after confirming retention and identity requirements.

## Candidate-specific hazards

### Anesthetic assessment candidate

The candidate's policies are role-based and do not themselves enforce facility scope. The live schema has since added restrictive facility policies and a trigger-based facility-lineage guard. The candidate also uses `ON DELETE CASCADE` from patient to assessment; patient-record retention and archive policy must be considered before any physical patient deletion is permitted.

### AI provenance candidate

The candidate's UPDATE policy has an operator-precedence hazard in its `WITH CHECK` expression:

```sql
(created_by = auth.uid() OR is_admin)
AND reviewed_by IS NULL
OR reviewed_by = auth.uid()
```

Because AND binds more tightly than OR, a user who sets `reviewed_by` to their own ID can satisfy the final branch without satisfying the creator/admin branch. The live catalog inspected for this review does not contain that candidate UPDATE policy; it contains SELECT policies and facility-lineage triggers instead. Do not reintroduce the candidate policy without rewriting and testing the intended authorization predicate.

The candidate also declares `actor_id NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL`, the same FK/nullability conflict confirmed in the live table.

## Required next verification

1. Recover provenance for each candidate independently (original commit/blob, deployment history, and matching live object definitions).
2. Inspect all later migrations that alter these three tables, policies, triggers, and RPCs before assigning a historical execution identity.
3. Resolve the AI event actor retention contract. If user deletion must not erase event history, a nullable actor FK with `ON DELETE SET NULL` plus immutable actor attribution metadata is one option; alternatively, `ON DELETE RESTRICT` requires an explicit account-retention/deactivation process. Do not choose without product, privacy, and audit requirements.
4. Preserve facility checks on every AI session/event read and write path. RLS and SECURITY DEFINER RPCs must be reviewed together.
5. Test both clean bootstrap and upgrade-from-hosted-baseline on disposable PostgreSQL 17/Supabase before any migration-chain repair is promoted.

## Safety boundary

No SQL was applied. No migration filename or version was changed. No patient or clinical data was modified. The collision remains unresolved pending source provenance and disposable replay.


## Follow-up catalog verification (2026-11-25)

A second read-only catalog pass confirmed that all three tables still have RLS enabled and that current AI session policies expose SELECT only; no direct INSERT/UPDATE policy was observed on `ai_clinical_sessions`. The live SECURITY DEFINER workflow surface includes `create_ai_clinical_session`, `get_ai_clinical_context`, `request_ai_clinical_analysis`, `record_ai_clinical_event`, and `enforce_ai_clinical_event_facility`. This confirms the current design has moved toward RPC-mediated AI session/event writes rather than the candidate's direct client write policies.

The current `anesthetic_assessments` policy set includes patient-owned read, staff role checks, and facility-identity policies for read/write paths. The AI event policy set exposes role-scoped SELECT; the event write RPC is the governed write surface.

The role-table-grant inspection also surfaced inherited client grants on these tables, including anon privileges on some operations. No anon policy was observed, so the result does not establish anon row access; RLS remains the row barrier. Nevertheless, inherited PUBLIC/anon table grants are broader than a least-privilege RPC-only model and should be reduced after callsite confirmation. This should be tracked as a separate forward-only ACL repair, not conflated with the historical collision.

The exact migration version `20260912010000` remains absent from the hosted ledger. No row data was queried, and no database changes were made.
