-- Restore explicit relationships required by PostgREST embedded resources and referential integrity.
ALTER TABLE public.service_orders DROP CONSTRAINT IF EXISTS service_orders_patient_id_fkey;
ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES public.patients(id) ON DELETE RESTRICT;
ALTER TABLE public.theatre_cases DROP CONSTRAINT IF EXISTS theatre_cases_patient_id_fkey;
ALTER TABLE public.theatre_cases ADD CONSTRAINT theatre_cases_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES public.patients(id) ON DELETE RESTRICT;
ALTER TABLE public.nursing_shift_handovers DROP CONSTRAINT IF EXISTS nursing_shift_handovers_patient_id_fkey;
ALTER TABLE public.nursing_shift_handovers ADD CONSTRAINT nursing_shift_handovers_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES public.patients(id) ON DELETE RESTRICT;
ALTER TABLE public.insurance_claims DROP CONSTRAINT IF EXISTS insurance_claims_patient_id_fkey;
ALTER TABLE public.insurance_claims ADD CONSTRAINT insurance_claims_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES public.patients(id) ON DELETE RESTRICT;
ALTER TABLE public.insurance_claims DROP CONSTRAINT IF EXISTS insurance_claims_invoice_id_fkey;
ALTER TABLE public.insurance_claims ADD CONSTRAINT insurance_claims_invoice_id_fkey FOREIGN KEY(invoice_id) REFERENCES public.invoices(id) ON DELETE RESTRICT;
ALTER TABLE public.prescriptions DROP CONSTRAINT IF EXISTS prescriptions_patient_id_fkey;
ALTER TABLE public.prescriptions ADD CONSTRAINT prescriptions_patient_id_fkey FOREIGN KEY(patient_id) REFERENCES public.patients(id) ON DELETE RESTRICT;
NOTIFY pgrst,'reload schema';
