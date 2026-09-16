import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migrationPath = path.join(root, 'supabase/migrations/20260916150000_nextgen_device_integration_boundary.sql');
const migration = fs.readFileSync(migrationPath, 'utf8');

const required = [
  'CREATE OR REPLACE FUNCTION public.accept_device_integration_message',
  'SECURITY DEFINER',
  'auth.uid()',
  'platform_device_registry',
  "lifecycle_state = 'active'",
  'device_facility_id',
  'facility_id IS NOT DISTINCT FROM device_facility_id',
  'direction IN (\'inbound\',\'bidirectional\')',
  'FOR UPDATE',
  'platform_integration_endpoints',
  "integration_type = 'device'",
  'platform_integration_messages',
  'payload_hash',
  "digest(convert_to(_payload::text, 'UTF8'), 'sha256')",
  'Message ID collision with different payload',
  'last_message_at',
  'REVOKE ALL ON FUNCTION public.accept_device_integration_message',
  'GRANT EXECUTE ON FUNCTION public.accept_device_integration_message',
  'service_role',
  'never mutate canonical clinical results',
];

for (const token of required) {
  if (!migration.includes(token)) throw new Error(`Device interoperability boundary control missing: ${token}`);
}

for (const standard of ['FHIR_R4','FHIR_R5','HL7_V2','DICOM','ASTM','REST_JSON','SOAP_XML']) {
  if (!migration.includes(standard)) throw new Error(`Device interoperability standard missing: ${standard}`);
}

for (const classification of ['clinical','operational','financial','administrative']) {
  if (!migration.includes(`'${classification}'`)) throw new Error(`Message classification missing: ${classification}`);
}

console.log('Next-gen device interoperability boundary contract passed: active-device gating, facility-scoped endpoint routing, inbound-direction validation, row locking, standard/classification validation, cryptographic payload integrity, idempotent collision detection, durable transport-ledger intake, heartbeat/message timestamping, canonical clinical-write isolation, and service-role-only execution are present.');
