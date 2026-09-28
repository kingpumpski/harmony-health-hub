# Ghana-aligned clinical reference values

## Purpose

Vital-sign helper/reference text is now read from the database-backed clinical_reference_values store rather than clinical ranges embedded in the React form.

The store requires:

- parameter and population scope
- source name and source reference
- source URL
- Ghana-specific vs international/supplemental classification
- effective date
- normal/reference range or threshold JSON
- user-facing display text
- last reviewed timestamp
- an automatically calculated 24-month review due date

Database constraints reject missing source names, non-HTTP(S) source URLs, missing source references/display text, and invalid min/max ordering.

## Seeded sources

| Parameter | Reference | Source |
|---|---|---|
| Blood pressure systolic | BP control target <140/90 mmHg; <130/80 mmHg with diabetes | Ghana MOH Standard Treatment Guideline, 2010 |
| Blood pressure diastolic | Same combined BP control targets | Ghana MOH Standard Treatment Guideline, 2010 |
| Combined blood pressure | Systolic/diastolic control targets | Ghana MOH Standard Treatment Guideline, 2010 |
| Body temperature | Axillary/infrared ≥37.5°C; core/rectal ≥38.5°C | MOH/GHS Guidelines for Case Management of Malaria in Ghana, 4th ed., 2020 |
| SpO₂ | 95–100% adult reference; <90% urgent oxygen/clinical threshold | WHO Pulse Oximetry Training Manual + WHO SARI oxygen toolkit |
| Heart rate | Adult pulse 60–100 bpm | WHO/ICRC Basic Emergency Care |
| Respiratory rate | Adult 10–20 breaths/min | WHO/ICRC Basic Emergency Care |
| Pain score | 0–10 numeric scale | WHO Emergency Unit Form |

## Safety boundaries

- The reference store is informational decision support; it does not replace clinician assessment or facility protocols.
- The reference store carries population scope. The current seeded vital references are adult-oriented unless explicitly marked otherwise.
- The UI does not show an administrator-only review flag to clinicians.
- SpO₂ oxygen wording intentionally points clinicians to the applicable protocol because oxygen targets can differ for pregnancy, emergency signs, chronic hypoxaemia and other conditions.
- Triage acuity thresholds already used by the application are not silently changed by this enhancement; harmonising those thresholds with a formal Ghana/WHO acuity model is a separate clinical-governance change.

## Administration

Administrators can review and edit the catalogue at /admin/clinical-references. The database remains the enforcement boundary: RLS permits active references to be read by authenticated users while inserts/updates require the administrator role.

## UI acceptance

The vital-sign helper component:

- displays the stored helper text directly beneath the input
- always includes source attribution and a source link
- uses aria-describedby
- wraps on narrow screens
- removes the previously hardcoded clinical ranges from the form placeholders
- preserves the existing form layout and write workflow

A browser screenshot/visual acceptance capture should be recorded during the manual browser acceptance pass after the PR is deployed; no visual result is claimed by the implementation-only test suite.
