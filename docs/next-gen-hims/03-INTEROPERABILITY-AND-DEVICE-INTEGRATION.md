# Interoperability and Medical Device Integration Specification

## Integration architecture

All external interfaces terminate at an integration boundary. Domain modules do not communicate directly with arbitrary device/vendor endpoints. Adapters normalize external messages into governed canonical events/resources and retain source provenance.

The integration boundary provides connection profiles, authentication, certificate/key lifecycle, message validation, schema/version checks, rate limits, queueing, retry policy, dead-letter handling, replay, reconciliation, monitoring and audit.

## Supported standards

- HL7 FHIR R4/R5 resource exchange, selected by implementation profile.
- HL7 v2.x for legacy ADT, orders, results and scheduling interfaces.
- DICOM for imaging acquisition, storage, worklist, query/retrieve and reporting workflows.
- ASTM E1381/E1394 where required by laboratory equipment.
- REST/JSON, XML and SOAP/Web Services for partner interfaces.
- Bulk Data Access for governed asynchronous population exchange.

## Laboratory integration

### Chemistry, hematology, immunoassay, urinalysis and microbiology
Each device registration declares manufacturer, model, firmware, protocol, connection endpoint, supported message version, specimen identifiers, result identifiers, units, reference ranges, QC state and calibration state.

Bidirectional interfaces support order transmission where the device permits it and result acquisition. Result messages are validated, associated to the correct order/specimen, normalized to canonical units/terminology, held when provenance is incomplete and released only through the laboratory validation workflow.

### Point-of-care devices
POCT workflows require operator identity, device identity, patient/specimen association, timestamp, result, units, quality status and location. Offline capture must preserve device and operator provenance and prevent silent duplicate uploads.

### Histopathology/cytology
Image/document provenance, specimen chain of custody, accession identifiers, pathology workflow state and final sign-off are mandatory. AI-assisted interpretation is advisory and cannot silently alter the signed report.

### Blood bank/transfusion
Blood-product identity, donation/product identifiers, compatibility testing, issue/return/disposition, administration, reaction and traceability events are linked end-to-end.

### Sample handling equipment
Centrifuge/incubator/sample-handler integrations track specimen location/state and exceptions. Equipment failures create operational events and never silently mark specimens complete.

## Imaging integration

The imaging boundary supports modality worklist, study lifecycle, PACS storage/retrieval, report linkage and structured reporting. Each study retains patient/order/accession/device/operator provenance.

Modality profiles cover X-ray/CR/DR, fluoroscopy, CT, MRI, ultrasound, nuclear medicine/PET-CT, mammography, interventional/C-arm, ophthalmic imaging, dermatology/endoscopy and dental imaging.

Dose-tracking data is retained where the modality supplies it. Teleradiology workflows require explicit remote-reader authorization, secure transfer, audit and final-report ownership.

## Device registry

Every connected device has a lifecycle: proposed → onboarding → validation → active → degraded/quarantined → maintenance → retired. Decommissioning preserves historical provenance while disabling new data flow.

## Error and reconciliation rules

Transient failures use bounded retries with exponential backoff. Permanent schema/authentication failures move to a dead-letter queue with operator-visible remediation. Replayed messages are idempotent. Reconciliation compares sent, received, accepted, rejected and released counts.

## Integration observability

Dashboards expose connection health, message latency, queue depth, error rate, rejection reason, retry count, dead-letter count, reconciliation drift and device availability. Logs are PHI-minimized and correlation identifiers are preferred over patient identifiers.

## Vendor neutrality

Vendor-specific mappings live in adapter configuration. Domain modules consume canonical resources/events and must not depend on a particular equipment vendor.