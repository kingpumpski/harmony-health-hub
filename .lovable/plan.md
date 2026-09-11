# Hospital workflow, patient hub and lab standards

A large upgrade, delivered in phases. Each phase is usable on its own.

## Phase 1 — Quick fixes and patient record hub

- Patient records become editable after registration (staff with the right role; every change is logged with who and when).
- Every form clears itself after a successful save, ready for the next entry.
- Sidebar scrollbar hidden (scrolling still works).
- New patient page opened from search: one window with the patient's full profile plus tabs for Appointments, Vitals/Triage, Encounters, Lab orders, Prescriptions, Billing, Documents and Admission. Each tab shows history and lets approved staff add or update entries without leaving the page.

## Phase 2 — Payment gating and service queues

- Any chargeable order (lab, imaging, procedure, drugs) is created as "pending payment approval".
- Accounts sees a queue, takes payment or grants an override, and the order is released to the target department.
- Departments only see released orders; pending ones show as blocked with the reason.
- A facility setting chooses the routing style: pay before every step, or the streamlined route (appointment → triage → consultation → accounts → diagnostics → consultation review → accounts → pharmacy).

## Phase 3 — Dashboard counters and daily flow

- Attending officer dashboard cards: Appointments today, Seen/attended, Awaiting lab review, Completed/discharged, and On admission.
- Each card opens the matching worklist page.
- Waiting room list for the day, with live notification when a patient is assigned to an officer.
- Inpatient flow: consultation → ward. Each inpatient review records "seen by <officer> at <time>" so the next officer and nurses can continue from there.

## Phase 4 — Triage entry

- "Start Triage" opens a patient picker (search or pick from today's waiting list), then a vitals form with auto BMI, priority scoring and critical alerts. Saves to the patient record.

## Phase 5 — Lab test catalogue and standard reports

- Lab test builder: define a test once with all its parameters, units, reference ranges and interpretation notes (WHO-aligned).
- Technicians entering results only fill in values; flags (low/normal/high) and interpretation come automatically.
- Printable standard report layout with patient details, parameters, units, reference ranges, flags, technician and approver.

## Phase 6 — Anesthetic assessment charts

- Adds visual charts: vitals trend, ASA/risk gauge, airway assessment radar, and a pre-op checklist completion bar.

## Phase 7 — Bulk upload rework

- Excel (.xlsx) templates in addition to CSV, for every entity including the system library.
- Templates download and re-upload cleanly with no errors.
- Re-uploading the same file adds only new rows; existing ones are reported as duplicates rather than failing the import.
- Per-row result report after each import.

## Phase 8 — Roles and AI specialists

- New "specialist nurse" role: everything a nurse can do, plus extended privileges (procedure notes, advanced monitoring, restricted medication administration).
- AI Clinical hub gains the missing specialists, including an AI Surgeon / Neurosurgeon view with a generated anatomical visualisation and a step-by-step reconstruction of the affected system to support planning of procedures.

## Technical notes

- New tables: `lab_test_catalog` + `lab_test_parameters`, `admissions` + `inpatient_reviews`, `service_orders` (payment gating), `facility_settings`, `patient_audit` via existing audit trigger; `app_role` gains `specialist_nurse`.
- Existing `department_queues` and `billing_overrides` are reused for the accounts release step.
- Patient hub is a new route `/patients/:id` composed of tab components that reuse the existing module pages' logic.
- Bulk upload uses SheetJS for `.xlsx` read/write; duplicate detection via natural keys (patient code, drug name+strength, ICD code, staff email) with upsert-ignore.
- AI surgeon visuals use Lovable AI image generation plus a labelled anatomy layer; no diagnostic claims, clearly marked as decision support.

## Order of work

I will start with Phase 1 and continue through the phases, reporting as each lands.
