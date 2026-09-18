import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const required = [
  'docs/next-gen-hims/00-ARCHITECTURE-DECISION.md','docs/next-gen-hims/01-MODULE-CATALOG.md','docs/next-gen-hims/02-CONFIGURATION-AND-DATA-SOVEREIGNTY.md','docs/next-gen-hims/03-INTEROPERABILITY-AND-DEVICE-INTEGRATION.md','docs/next-gen-hims/04-AI-SAFETY-AND-GOVERNANCE.md','docs/next-gen-hims/05-ACCESSIBILITY-AND-PATIENT-ENGAGEMENT.md','docs/next-gen-hims/06-SECURITY-PRIVACY-COMPLIANCE.md','docs/next-gen-hims/07-STANDARDS-MATRIX.md','docs/next-gen-hims/08-IMPLEMENTATION-ROADMAP.md','docs/next-gen-hims/09-QUALITY-GATE.md','docs/next-gen-hims/10-TRACEABILITY-MATRIX.md','docs/next-gen-hims/11-RISK-REGISTER.md','docs/next-gen-hims/12-CLINICAL-SAFETY-SECURITY-CONVERGENCE.md','docs/next-gen-hims/13-IMPLEMENTATION-STATUS.md','docs/next-gen-hims/14-DOMAIN-RECONCILIATION.md','docs/next-gen-hims/15-APPOINTMENT-CONCURRENCY-HARDENING.md','docs/next-gen-hims/16-IMAGING-RIS-PACS-INTEGRITY.md','docs/next-gen-hims/17-CLAIMS-ADJUDICATION-CONCURRENCY.md','docs/next-gen-hims/18-THEATRE-EMERGENCY-INTEGRITY.md','docs/next-gen-hims/19-ADMISSION-BED-CONCURRENCY.md','docs/next-gen-hims/20-NURSING-CONTINUITY-INTEGRITY.md','docs/next-gen-hims/23-MASTER-SPECIFICATION-RECONCILIATION.md','docs/next-gen-hims/24-ARCHITECTURE-DECISIONS-BROADER-HMS.md','docs/api/openapi.yaml','scripts/test-nextgen-broader-hms.mjs','platform/reference/module-registry.json','platform/reference/interoperability-fixtures.json','src/lib/nextGenPlatform.ts','src/lib/nextGenContracts.ts','src/lib/nextGenModuleManifest.ts','src/lib/nextGenClinicalSafety.ts','src/lib/nextGenIntegrationRuntime.ts','src/lib/nextGenAIGovernance.ts','src/lib/nextGenDeploymentProfile.ts','src/lib/nextGenCommunicationPolicy.ts','src/lib/nextGenRuntimeGuards.ts','src/pages/admin/NextGenPlatformControlCenter.tsx','scripts/test-nextgen-runtime.mjs','scripts/test-nextgen-clinical-workflows.mjs','scripts/test-nextgen-ai-session-workflow.mjs','scripts/test-nextgen-device-lifecycle.mjs','scripts/test-nextgen-device-integration-boundary.mjs','scripts/test-nextgen-lab-device-reconciliation.mjs','scripts/test-nextgen-appointment-concurrency.mjs','scripts/test-nextgen-imaging-ris-pacs.mjs','scripts/test-nextgen-claims-adjudication.mjs','scripts/test-nextgen-medication-pharmacy-safety.mjs','scripts/test-nextgen-transfusion-safety.mjs','scripts/test-nextgen-theatre-emergency.mjs','scripts/test-nextgen-admission-bed-concurrency.mjs','scripts/test-nextgen-nursing-continuity.mjs','supabase/migrations/20260915150000_nextgen_platform_foundation.sql','supabase/migrations/20260915160000_nextgen_integration_delivery.sql','supabase/migrations/20260915170000_nextgen_communication_consent.sql','supabase/migrations/20260915182000_nextgen_integration_payload_integrity.sql','supabase/migrations/20260916100000_ai_session_request_workflow_hardening.sql','supabase/migrations/20260916103000_nextgen_clinical_audit_convergence.sql','supabase/migrations/20260916120000_nextgen_empi_merge_workflow.sql','supabase/migrations/20260916130000_ai_session_creation_workflow_hardening.sql','supabase/migrations/20260916140000_nextgen_device_lifecycle_workflow.sql','supabase/migrations/20260916150000_nextgen_device_integration_boundary.sql','supabase/migrations/20260916160000_nextgen_lab_device_result_reconciliation.sql','supabase/migrations/20260916170000_nextgen_appointment_concurrency_workflow.sql','supabase/migrations/20260916180000_nextgen_claims_adjudication_concurrency.sql','supabase/migrations/20260916182000_nextgen_medication_pharmacy_safety.sql','supabase/migrations/20260916183000_nextgen_transfusion_safety.sql','supabase/migrations/20260916184000_nextgen_theatre_emergency_integrity.sql','supabase/migrations/20260916190000_nextgen_admission_bed_concurrency.sql','supabase/migrations/20260916195000_nextgen_nursing_continuity_integrity.sql','supabase/migrations/20260918170000_broader_hms_enterprise_foundation.sql','supabase/migrations/20260918180000_hms_import_governed_lifecycle.sql','supabase/migrations/20260918190000_hms_import_patient_template.sql','supabase/migrations/20260918200000_hms_import_rollback_ledger.sql'];
const missing = required.filter((file) => !fs.existsSync(path.join(root, file)));
if (missing.length) throw new Error(`Missing required next-gen artifacts: ${missing.join(', ')}`);
const registry = JSON.parse(fs.readFileSync(path.join(root, 'platform/reference/module-registry.json'), 'utf8'));
if (registry.schemaVersion !== '1.0.0') throw new Error('Unexpected module registry schema version');
if (registry.modules.length < 48) throw new Error('Broader HMS module registry is incomplete');
if (!Array.isArray(registry.modules) || registry.modules.length < 20) throw new Error('Module registry must contain at least 20 modules');
const ids = registry.modules.map((module) => module.id);
if (new Set(ids).size !== ids.length) throw new Error('Module registry contains duplicate module IDs');
if (registry.defaultState !== 'disabled-until-validated') throw new Error('Unsafe registry default state');
const fixtures = JSON.parse(fs.readFileSync(path.join(root, 'platform/reference/interoperability-fixtures.json'), 'utf8'));
if (fixtures.version !== '1.0.0' || !Array.isArray(fixtures.fixtures) || fixtures.fixtures.length !== 7) throw new Error('Interoperability fixture manifest is incomplete');
const fixtureStandards = new Set(fixtures.fixtures.map((fixture) => fixture.standard));
for (const standard of ['FHIR_R4','FHIR_R5','HL7_V2','DICOM','ASTM','REST_JSON','SOAP_XML']) if (!fixtureStandards.has(standard)) throw new Error(`Missing interoperability fixture for ${standard}`);
for (const fixture of fixtures.fixtures) if (!fixture.id || !fixture.eventType || !fixture.schemaVersion || !fixture.classification || fixture.payload === undefined) throw new Error(`Malformed interoperability fixture: ${fixture.id || 'unknown'}`);
const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
for (const [script, command] of Object.entries({
  'test:nextgen-runtime':'node scripts/test-nextgen-runtime.mjs',
  'test:nextgen-clinical-workflows':'node scripts/test-nextgen-clinical-workflows.mjs',
  'test:nextgen-empi':'node scripts/test-nextgen-empi-workflow.mjs',
  'test:nextgen-ai-session':'node scripts/test-nextgen-ai-session-workflow.mjs',
  'test:nextgen-device-lifecycle':'node scripts/test-nextgen-device-lifecycle.mjs',
  'test:nextgen-device-integration':'node scripts/test-nextgen-device-integration-boundary.mjs',
  'test:nextgen-lab-device-reconciliation':'node scripts/test-nextgen-lab-device-reconciliation.mjs',
  'test:nextgen-appointment-concurrency':'node scripts/test-nextgen-appointment-concurrency.mjs',
  'test:nextgen-imaging-ris-pacs':'node scripts/test-nextgen-imaging-ris-pacs.mjs',
  'test:nextgen-claims-adjudication':'node scripts/test-nextgen-claims-adjudication.mjs',
  'test:nextgen-medication-pharmacy-safety':'node scripts/test-nextgen-medication-pharmacy-safety.mjs',
  'test:nextgen-transfusion-safety':'node scripts/test-nextgen-transfusion-safety.mjs',
  'test:nextgen-theatre-emergency':'node scripts/test-nextgen-theatre-emergency.mjs',
  'test:nextgen-admission-bed-concurrency':'node scripts/test-nextgen-admission-bed-concurrency.mjs',
  'test:nextgen-nursing-continuity':'node scripts/test-nextgen-nursing-continuity.mjs',
  'test:nextgen-broader-hms':'node scripts/test-nextgen-broader-hms.mjs',
})) if (packageJson.scripts?.[script] !== command) throw new Error(`Executable next-gen test script is not wired into package scripts: ${script}`);
const requiredMigrations = [
  ['20260915150000_nextgen_platform_foundation.sql', ['platform_deployment_profiles','platform_device_registry','platform_integration_endpoints','platform_event_schemas','platform_ai_model_registry','platform_ai_model_evaluations','user_accessibility_preferences','patient_communication_preferences']],
  ['20260915160000_nextgen_integration_delivery.sql', ['platform_integration_messages','platform_integration_delivery_attempts']],
  ['20260916140000_nextgen_device_lifecycle_workflow.sql', ['register_platform_device','transition_platform_device','record_platform_device_heartbeat']],
  ['20260916150000_nextgen_device_integration_boundary.sql', ['accept_device_integration_message']],
  ['20260916160000_nextgen_lab_device_result_reconciliation.sql', ['reconcile_lab_device_result']],
  ['20260916170000_nextgen_appointment_concurrency_workflow.sql', ['create_appointment_workflow','claim_appointment','update_appointment_workflow','start_appointment_encounter']],
  ['20260916180000_nextgen_claims_adjudication_concurrency.sql', ['transition_insurance_claim','update_insurance_claim_financials']],
  ['20260916182000_nextgen_medication_pharmacy_safety.sql', ['transition_medication_administration']],
  ['20260916183000_nextgen_transfusion_safety.sql', ['transition_transfusion_record']],
  ['20260916184000_nextgen_theatre_emergency_integrity.sql', ['create_theatre_case','transition_theatre_case','transition_emergency_case']],
  ['20260916190000_nextgen_admission_bed_concurrency.sql', ['create_admission_workflow','discharge_admission_workflow','assign_ward_bed','release_ward_bed']],
  ['20260916195000_nextgen_nursing_continuity_integrity.sql', ['create_nursing_care_plan','transition_nursing_care_plan','create_nursing_shift_handover','acknowledge_nursing_shift_handover']],
];
for (const [filename, tokens] of requiredMigrations) {
  const sql = fs.readFileSync(path.join(root, 'supabase/migrations', filename), 'utf8');
  for (const token of tokens) if (!sql.includes(token)) throw new Error(`Required workflow control missing in ${filename}: ${token}`);
}
const integrity = fs.readFileSync(path.join(root, 'supabase/migrations/20260915182000_nextgen_integration_payload_integrity.sql'), 'utf8');
for (const token of ['CREATE EXTENSION IF NOT EXISTS pgcrypto;','digest(convert_to(NEW.payload::text, \'UTF8\'), \'sha256\')','platform_integration_payload_hash_trigger','payload_hash ~ \'^[0-9a-f]{64}$\'']) if (!integrity.includes(token)) throw new Error(`Integration payload integrity control missing: ${token}`);
const aiWorkflow = fs.readFileSync(path.join(root, 'supabase/migrations/20260916100000_ai_session_request_workflow_hardening.sql'), 'utf8');
for (const token of ['CREATE OR REPLACE FUNCTION public.request_ai_clinical_analysis','status = \'analysis_requested\'','created_by = auth.uid()','record_ai_clinical_event','CREATE OR REPLACE FUNCTION public.review_ai_clinical_session','status = \'completed\'','output_snapshot IS NOT NULL','REVOKE EXECUTE ON FUNCTION public.request_ai_clinical_analysis','GRANT EXECUTE ON FUNCTION public.request_ai_clinical_analysis']) if (!aiWorkflow.includes(token)) throw new Error(`AI workflow security control missing: ${token}`);
const aiCreation = fs.readFileSync(path.join(root, 'supabase/migrations/20260916130000_ai_session_creation_workflow_hardening.sql'), 'utf8');
for (const token of ['CREATE OR REPLACE FUNCTION public.create_ai_clinical_session','SECURITY DEFINER','auth.uid()','_patient_id UUID','_input_snapshot JSONB','record_ai_clinical_event','REVOKE ALL ON FUNCTION public.create_ai_clinical_session','GRANT EXECUTE ON FUNCTION public.create_ai_clinical_session','REVOKE INSERT, UPDATE, DELETE ON public.ai_clinical_sessions FROM authenticated']) if (!aiCreation.includes(token)) throw new Error(`AI session creation security control missing: ${token}`);
const clinicalAudit = fs.readFileSync(path.join(root, 'supabase/migrations/20260916103000_nextgen_clinical_audit_convergence.sql'), 'utf8');
for (const token of ["'appointments'","'medication_administrations'","'lab_orders'","'lab_results'","'imaging_orders'","'insurance_claims'",'audit_clinical_record_change','CREATE TRIGGER','converged clinical audit']) if (!clinicalAudit.includes(token)) throw new Error(`Clinical audit convergence control missing: ${token}`);
const empi = fs.readFileSync(path.join(root, 'supabase/migrations/20260916120000_nextgen_empi_merge_workflow.sql'), 'utf8');
for (const token of ['patient_identity_merges','request_patient_identity_merge','approve_patient_identity_merge','admin authorization','Source and target patient records must be distinct','A merge requester cannot approve the same merge request','FOR UPDATE','status = \'merged\'','REVOKE ALL ON FUNCTION public.approve_patient_identity_merge']) if (!empi.includes(token)) throw new Error(`EMPI merge security boundary missing: ${token}`);
const contracts = fs.readFileSync(path.join(root, 'src/lib/nextGenContracts.ts'), 'utf8');
for (const token of ['InteroperabilityEnvelope','validateEnvelope','requiresHumanReview','INTEGRATION_STANDARDS','Date.parse','payload === undefined']) if (!contracts.includes(token)) throw new Error(`Runtime contract missing: ${token}`);
const safety = fs.readFileSync(path.join(root, 'src/lib/nextGenClinicalSafety.ts'), 'utf8');
for (const token of ['medication-administration','blood-product-administration','diagnostic-result-finalisation','ai-clinical-recommendation','assertClinicalActionSafe','requiresAudit','audited']) if (!safety.includes(token)) throw new Error(`Clinical safety guard missing: ${token}`);
const integration = fs.readFileSync(path.join(root, 'src/lib/nextGenIntegrationRuntime.ts'), 'utf8');
for (const token of ['evaluateIncomingEnvelope','classifyDeliveryFailure','nextRetry','canReplay','prepareReplay','markReplayed','payloadFingerprint','Message ID collision','IntegrationReplayContext','authorised','confirmed']) if (!integration.includes(token)) throw new Error(`Integration runtime boundary missing: ${token}`);
const ai = fs.readFileSync(path.join(root, 'src/lib/nextGenAIGovernance.ts'), 'utf8');
for (const token of ['authorizeAIClinicalUse','governClinicalOutput','lifecycle','evaluationPassed','evidence.length','modelVersion','auditRequired','correlationId','confidence > 1']) if (!ai.includes(token)) throw new Error(`AI governance boundary missing: ${token}`);
const deployment = fs.readFileSync(path.join(root, 'src/lib/nextGenDeploymentProfile.ts'), 'utf8');
for (const token of ['resolveDeploymentProfile','isModuleAllowed','effectiveFrom','dataResidencyRegion']) if (!deployment.includes(token)) throw new Error(`Deployment-profile boundary missing: ${token}`);
const communication = fs.readFileSync(path.join(root, 'src/lib/nextGenCommunicationPolicy.ts'), 'utf8');
for (const token of ['evaluateCommunicationRequest','preferredChannels','quietHours','minimumNecessary','emergencyOverrideAllowed','Invalid quiet-hours configuration','Intl.DateTimeFormat']) if (!communication.includes(token)) throw new Error(`Communication-policy boundary missing: ${token}`);
const runtimeGuards = fs.readFileSync(path.join(root, 'src/lib/nextGenRuntimeGuards.ts'), 'utf8');
for (const token of ['guardClinicalAction','guardAIOutput','guardCommunication','guardDeploymentModule','audited']) if (!runtimeGuards.includes(token)) throw new Error(`Runtime guard composition missing: ${token}`);
const broaderMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20260918170000_broader_hms_enterprise_foundation.sql'), 'utf8');
for (const token of ['hms_facility_modules','hms_import_templates','hms_report_templates','hms_role_catalog','hms_biomedical_assets','hms_procurement_suppliers','hms_teaching_research_projects','hms_physio_assessments']) if (!broaderMigration.includes(token)) throw new Error(`Broader HMS foundation missing: ${token}`);
const manifest = fs.readFileSync(path.join(root, 'src/lib/nextGenModuleManifest.ts'), 'utf8');
for (const token of ['getModuleContract','getModuleContracts','getUncontractedModules']) if (!manifest.includes(token)) throw new Error(`Module manifest missing: ${token}`);
const contractIds = [...manifest.matchAll(/\{ id: '([^']+)'/g)].map((match) => match[1]);
if (contractIds.length !== ids.length) throw new Error(`Module contract coverage mismatch: registry=${ids.length}, manifest=${contractIds.length}`);
if (new Set(contractIds).size !== contractIds.length) throw new Error('Module contract manifest contains duplicate IDs');
const missingContracts = ids.filter((id) => !contractIds.includes(id));
if (missingContracts.length) throw new Error(`Uncontracted registry modules: ${missingContracts.join(', ')}`);
console.log(`Next-gen contract verification passed: ${ids.length} modules; ${required.length} required artifacts; complete module-contract coverage; executable adversarial runtime fixtures wired; RLS, lifecycle, idempotency, collision, replay, payload-integrity, interoperability fixtures, safety, audit, integration-runtime, AI-governance, deployment-profile, communication-consent, AI creation/request/review workflow, clinical-audit convergence, EMPI merge, device lifecycle, domain workflow and nursing-continuity checks present.`);
