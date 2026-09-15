# Domain Reconciliation Contract

The reference platform must extend Harmony Health Hub without creating parallel clinical truth. Existing routes and canonical tables are authoritative until a documented migration proves otherwise.

## Reconciliation rules

- Patient identity, appointments, encounters, laboratory, imaging, pharmacy, maternity, fertility, dental, billing, claims and existing inpatient workflows are reused where already implemented.
- New capabilities are introduced at explicit boundaries: contracts, adapters, governance, configuration, reporting, or missing workflow states.
- A new table is justified only when the existing schema cannot represent the capability without unsafe ambiguity or destructive change.
- A new RPC must have an explicit authorization contract, input validation, transactional behavior and audit semantics.
- Clinical writes must never rely on local-storage state as the source of truth.
- Offline queues may stage work but cannot bypass server-side authorization or safety rules when synchronized.
- Integration messages must be idempotent and replayable without double-applying a clinical or financial effect.
- AI outputs are recommendations or documentation assistance; they cannot silently finalize diagnoses, orders, results, prescriptions or other clinical decisions.

## Existing coverage identified during reconciliation

The repository already contains dedicated surfaces for appointments, patient registration/search/hub, encounters, laboratory, imaging, pharmacy, medication administration, admissions, ward beds, nursing handover, emergency, theatre, transfusion, maternity, fertility, dental, ophthalmology, telemedicine, billing, insurance claims, reports, roster/shift management, patient portal/chat and AI clinical tooling. The reference architecture therefore treats these as canonical surfaces and concentrates new work on cross-cutting contracts and genuinely missing capabilities.

## Completion criterion

A domain is promoted only after its UI, routing, permissions, database/RLS, workflow, audit, notifications/integration, error recovery and tests are coherent. A route or placeholder page alone is not considered implementation.
