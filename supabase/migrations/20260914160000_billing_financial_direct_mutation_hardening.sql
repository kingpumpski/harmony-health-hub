-- Billing/financial mutation-surface hardening.
-- Payment and invoice state must remain behind the existing billing RPCs.
-- Do not remove the read path; the UI already uses pay_selected_invoice_items().

REVOKE INSERT, UPDATE, DELETE ON public.payments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.invoices FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.invoice_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.invoice_item_payments FROM authenticated;

-- Billing workflows remain available through their existing authenticated RPCs.
REVOKE ALL ON FUNCTION public.pay_selected_invoice_items(UUID, UUID[], TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_selected_invoice_items(UUID, UUID[], TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;

REVOKE ALL ON FUNCTION public.refresh_invoice_totals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_invoice_totals() TO authenticated;
