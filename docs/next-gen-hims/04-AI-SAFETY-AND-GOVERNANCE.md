# AI Doctor Framework and Clinical Safety Specification

## Operating model

AI assistants are clinical decision-support systems. They summarize, retrieve, draft, suggest, flag and explain; they do not independently diagnose, prescribe, dose, discharge, consent, or close a safety-critical workflow.

Every AI interaction identifies the model/version, context timestamp, relevant patient-data sources, external sources used, confidence/uncertainty, generated recommendation and human disposition.

## Specialty assistants

The platform defines governed personas for general practice, internal medicine, pediatrics, obstetrics/gynecology, cardiology, neurology, oncology, infectious disease, emergency medicine, surgery, psychiatry/mental health, dermatology, ophthalmology, orthopedics, radiology, pathology, laboratory medicine, anesthesia, nephrology, endocrinology, gastroenterology, pulmonology, rheumatology, hematology, urology, ENT, family medicine, geriatrics, palliative care, public health and pharmacovigilance.

Each persona has a declared scope, prohibited actions, input requirements, source policy, escalation rules, confidence thresholds, specialty-specific evaluation suite and human-review requirement.

## Shared capabilities

Ambient documentation, differential support, medication safety support, image/report assistance, laboratory interpretation, risk scoring, care-pathway suggestions, triage support, coding assistance, translation/terminology normalization, operational prediction and patient communication are delivered through a common safety envelope.

## Human oversight

High-risk suggestions require explicit clinician acknowledgement. The system records acceptance, rejection, modification, override and reason where required. A clinician can always decline AI assistance without losing access to the underlying record.

AI-generated patient-facing content requires appropriate disclosure and must be bounded by approved content/policy controls. Emergency workflows provide escalation to human care rather than presenting AI output as a final clinical decision.

## Source governance

Clinical recommendations should cite approved guidelines, institutional protocols and validated knowledge sources. Source freshness is tracked. Conflicting sources are surfaced rather than silently reconciled.

## Model lifecycle

Model states: proposed → validated → approved → active → monitored → restricted/suspended → retired. Every release has evaluation evidence, intended-use statement, prohibited-use statement, data provenance, bias assessment, security assessment and rollback path.

## Safety controls

- confidence thresholds are configurable by use case;
- high-risk outputs require human review;
- no autonomous medication ordering or dosing;
- no silent modification of signed clinical records;
- uncertainty is explicit;
- source provenance is retained;
- prompt/context injection defenses are required;
- patient data sent to a model is minimized and governed;
- model output is isolated from executable system commands;
- incidents are reportable and traceable;
- drift and fairness are monitored.

## Clinical safety governance

AI hazards join the system clinical risk register. Safety cases cover incorrect recommendation, omitted warning, automation bias, hallucinated source, stale guideline, biased performance, prompt injection, data leakage, identity mix-up and workflow over-reliance.

## Specialty safety examples

Radiology/pathology assistants may flag or annotate but cannot sign final reports. Medication assistants may identify interactions or dosing concerns but cannot create a medication order. Triage assistants may prioritize for human review but cannot deny emergency care. Pharmacovigilance assistants may detect signals but cannot independently establish causality.

## Regulatory posture

The platform uses risk-based governance aligned with applicable FDA/EMA/WHO and national requirements. A feature is classified before deployment to determine whether it is ordinary workflow assistance, clinical decision support, or potentially regulated medical-device software.

## Monitoring

Production monitoring includes quality, safety incidents, false-positive/false-negative patterns, latency, model drift, source freshness, demographic fairness and override rates. Monitoring is separated from PHI-rich clinical records wherever possible.