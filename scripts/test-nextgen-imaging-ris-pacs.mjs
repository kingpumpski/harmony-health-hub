import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20260916180000_nextgen_imaging_ris_pacs_integrity.sql', 'utf8');
const lifecycle = fs.readFileSync('supabase/migrations/20260914130000_imaging_lifecycle_server_authority.sql', 'utf8');
const source = fs.readFileSync('supabase/migrations/20260912003000_phase2_pharmacy_procedure_imaging_gates.sql', 'utf8');

for (const token of [
  'ALTER TABLE public.imaging_orders',
  'accession_number TEXT',
  'dicom_study_uid TEXT',
  'pacs_reference TEXT',
  'acquisition_status TEXT',
  "'not_started','acquiring','acquired','failed','cancelled'",
  'acquired_at TIMESTAMPTZ',
  'report_finalized_by UUID',
  'report_finalized_at TIMESTAMPTZ',
  'uq_imaging_orders_dicom_study_uid',
  'uq_imaging_orders_accession_number',
  'CREATE OR REPLACE FUNCTION public.record_imaging_acquisition',
  'Clinical staff required',
  'FOR UPDATE',
  'in-progress order',
  'DICOM study UID is already associated',
  'Accession number is already associated',
  "acquisition_status = 'acquired'",
  'CREATE OR REPLACE FUNCTION public.finalize_imaging_report',
  'Imaging acquisition must be reconciled before report finalization',
  'report_finalized_at IS NOT NULL',
  "status = 'completed'",
  'REVOKE INSERT, UPDATE, DELETE ON TABLE public.imaging_orders FROM authenticated',
  'audit_clinical_record_change',
]) if (!migration.includes(token)) throw new Error(`Imaging RIS/PACS control missing: ${token}`);

for (const token of [
  'CREATE OR REPLACE FUNCTION public.start_imaging_order',
  'CREATE OR REPLACE FUNCTION public.complete_imaging_order',
  'FOR UPDATE',
  'REVOKE UPDATE, DELETE ON TABLE public.imaging_orders FROM authenticated',
]) if (!lifecycle.includes(token)) throw new Error(`Existing imaging lifecycle boundary missing: ${token}`);

for (const token of [
  'CREATE TABLE IF NOT EXISTS public.imaging_orders',
  'service_order_id UUID',
  'create_imaging_order_with_payment_gate',
]) if (!source.includes(token)) throw new Error(`Canonical imaging foundation missing: ${token}`);

console.log('Next-gen imaging RIS/PACS contract passed: acquisition identity, DICOM/PACS reconciliation, duplicate protection, server-authoritative report finalization, direct-write lockdown, and canonical audit boundary present.');
