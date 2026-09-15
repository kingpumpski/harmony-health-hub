# Standards and Compliance Traceability Matrix

| Standard / framework | Target use | Architecture response | Validation evidence |
|---|---|---|---|
| HL7 FHIR R4/R5 | modern exchange | governed FHIR boundary + implementation profiles | resource/validation/round-trip tests |
| HL7 v2.x | legacy ADT/orders/results | adapter layer + message provenance | fixture and replay tests |
| SNOMED CT | clinical terminology | versioned terminology service | concept/version/mapping tests |
| LOINC | laboratory observations | canonical lab coding | order/result mapping tests |
| ICD-11 | diagnosis/reporting | jurisdiction-aware coding layer | code-set validation |
| DICOM | imaging | modality/PACS/RIS adapter | DICOM workflow tests |
| ASTM E1381/E1394 | laboratory equipment | device adapter boundary | message conformance tests |
| HL7 Bulk Data Access | asynchronous export | governed bulk export service | scope/authorization/export tests |
| OAuth 2.0 / OIDC | identity/API access | federated identity boundary | token/session/negative tests |
| WCAG 2.2 AA | accessibility | accessible design system and workflows | automated + manual + assistive-tech tests |
| Section 508 | US accessibility | mapped accessibility acceptance criteria | VPAT-style evidence where required |
| EN 301 549 | EU accessibility | accessibility requirements mapped to components | conformance evidence |
| ADA | US disability access | inclusive workflow requirements | manual workflow review |
| ISO/IEC 27001 | information security | ISMS-aligned control catalogue | control/evidence mapping |
| ISO/IEC 27017 | cloud security | cloud control profile | cloud configuration evidence |
| ISO/IEC 27018 | cloud privacy | PII/PHI cloud privacy controls | data-handling evidence |
| GDPR | EU privacy | purpose, rights, minimization, residency/transfer controls | DPIA and rights workflow tests |
| HIPAA | US health data | minimum necessary, audit, security/privacy controls | control mapping |
| Australian Privacy Act / My Health Record | Australia | jurisdiction profile and integration boundary | profile-specific compliance tests |
| ISO 14971 | medical-device risk where applicable | clinical risk register and hazard controls | risk file |
| IEC 62304 | medical-device software where applicable | lifecycle and safety classification | lifecycle evidence |
| ISO 13485 | medical-device QMS where applicable | quality-system mapping | QMS evidence |
| FDA / EMA / WHO AI guidance | AI governance | intended use, human oversight, validation, monitoring | model dossier and surveillance records |

## Compliance rule

The matrix is an engineering traceability tool and is not a legal certification. A deployment may claim compliance only after the applicable jurisdictional assessment, required controls, evidence and external review have been completed.

## Conflict resolution

Where jurisdictional requirements differ, the strictest applicable security/privacy control is the safe default unless a jurisdiction explicitly requires a different lawful process. Clinical and legal requirements that cannot be harmonized are represented as deployment-profile policy rather than conditional logic scattered through modules.