-- Batch 9: harden remaining high-impact clinical/financial workflow SECURITY DEFINER paths.
-- Search-path hardening only; signatures, role gates, and workflow behavior are preserved.
ALTER FUNCTION public.pay_selected_invoice_items(uuid,uuid[],text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.reconcile_discharge_billing(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.record_fertility_monitoring_workflow(uuid,date,integer,numeric,numeric,numeric,numeric,integer,integer,numeric,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.record_maternity_observation_workflow(uuid,text,integer,numeric,integer,integer,numeric,integer,text,text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.record_transfusion_event(uuid,text,boolean,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.register_outside_lab_document(uuid,text,text,text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.release_service_order(uuid,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.reopen_medication_administration(uuid,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.review_ophthalmology_exam(uuid,jsonb) SET search_path = pg_catalog, public;
ALTER FUNCTION public.schedule_patient_referral_workflow(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.schedule_video_session(uuid,timestamp with time zone,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.start_imaging_order(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.start_video_session(uuid) SET search_path = pg_catalog, public;
ALTER FUNCTION public.transition_emergency_case(uuid,text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.transition_fertility_cycle_workflow(uuid,text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.transition_theatre_case(uuid,text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.update_appointment_workflow(uuid,timestamp with time zone,text,text,text,text) SET search_path = pg_catalog, public;
ALTER FUNCTION public.update_insurance_case(uuid,text,text,text,numeric,numeric,text) SET search_path = pg_catalog, public;