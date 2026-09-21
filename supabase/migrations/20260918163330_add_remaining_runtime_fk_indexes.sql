-- Runtime foreign-key indexes identified by the Supabase performance advisor.
-- These indexes support audit, migration, authorization, and service-order lookup paths.
CREATE INDEX IF NOT EXISTS idx_data_migration_batches_approved_by ON public.data_migration_batches(approved_by);
CREATE INDEX IF NOT EXISTS idx_data_migration_batches_created_by ON public.data_migration_batches(created_by);
CREATE INDEX IF NOT EXISTS idx_data_migration_rows_approved_by ON public.data_migration_rows(approved_by);
CREATE INDEX IF NOT EXISTS idx_data_migration_rows_patient_id ON public.data_migration_rows(patient_id);
CREATE INDEX IF NOT EXISTS idx_data_migration_rows_promoted_by ON public.data_migration_rows(promoted_by);
CREATE INDEX IF NOT EXISTS idx_data_migration_rows_reconciled_by ON public.data_migration_rows(reconciled_by);
CREATE INDEX IF NOT EXISTS idx_document_versions_changed_by ON public.document_versions(changed_by);
CREATE INDEX IF NOT EXISTS idx_legacy_clinical_records_approved_by ON public.legacy_clinical_records(approved_by);
CREATE INDEX IF NOT EXISTS idx_legacy_clinical_records_batch_id ON public.legacy_clinical_records(batch_id);
CREATE INDEX IF NOT EXISTS idx_legacy_clinical_records_imported_by ON public.legacy_clinical_records(imported_by);
CREATE INDEX IF NOT EXISTS idx_legacy_clinical_records_reconciled_by ON public.legacy_clinical_records(reconciled_by);
CREATE INDEX IF NOT EXISTS idx_patient_audit_log_patient_id ON public.patient_audit_log(patient_id);
CREATE INDEX IF NOT EXISTS idx_patient_visit_authorizations_activated_by ON public.patient_visit_authorizations(activated_by);
CREATE INDEX IF NOT EXISTS idx_patient_visit_authorizations_appointment_id ON public.patient_visit_authorizations(appointment_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission_key ON public.role_permissions(permission_key);
CREATE INDEX IF NOT EXISTS idx_service_order_events_actor_id ON public.service_order_events(actor_id);
CREATE INDEX IF NOT EXISTS idx_system_master_data_created_by ON public.system_master_data(created_by);
