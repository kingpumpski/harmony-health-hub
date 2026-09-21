-- Cover frequently joined/audited foreign keys identified by Supabase performance advisor.
CREATE INDEX IF NOT EXISTS idx_billing_tariff_adjustments_adjusted_by ON public.billing_tariff_adjustments(adjusted_by);
CREATE INDEX IF NOT EXISTS idx_billing_tariff_adjustments_service_order_id ON public.billing_tariff_adjustments(service_order_id);
CREATE INDEX IF NOT EXISTS idx_encounters_admission_id ON public.encounters(admission_id);
CREATE INDEX IF NOT EXISTS idx_encounters_submitted_by ON public.encounters(submitted_by);
CREATE INDEX IF NOT EXISTS idx_invoice_item_payments_payment_id ON public.invoice_item_payments(payment_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_paid_by ON public.invoice_items(paid_by);
CREATE INDEX IF NOT EXISTS idx_patient_audit_log_changed_by ON public.patient_audit_log(changed_by);
