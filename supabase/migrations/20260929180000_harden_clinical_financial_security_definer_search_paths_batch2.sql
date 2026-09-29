-- Batch 2: remove mutable public search_path from high-impact clinical/financial SECURITY DEFINER RPCs.
alter function public.activate_patient_visit_coverage(uuid, text, uuid, date) set search_path = pg_catalog, public;
alter function public.adjust_invoice_item_tariff(uuid, numeric, text, text) set search_path = pg_catalog, public;
alter function public.cancel_service_order(uuid, text) set search_path = pg_catalog, public;
alter function public.complete_encounter_workflow(uuid) set search_path = pg_catalog, public;
alter function public.create_encounter_workflow(uuid, text, text) set search_path = pg_catalog, public;
alter function public.create_imaging_order_with_payment_gate(uuid, uuid, text, text, text, text, text, numeric) set search_path = pg_catalog, public;
alter function public.create_lab_order_with_payment_gate(uuid, text, text, text, text, numeric, uuid) set search_path = pg_catalog, public;
alter function public.create_nursing_note(uuid, text, text, text, text, text, uuid, uuid) set search_path = pg_catalog, public;
alter function public.create_patient_referral_workflow(uuid, text, text, text, text, text) set search_path = pg_catalog, public;
alter function public.create_procedure_note(uuid, text, text, text, text, text, text, text, numeric, uuid) set search_path = pg_catalog, public;
