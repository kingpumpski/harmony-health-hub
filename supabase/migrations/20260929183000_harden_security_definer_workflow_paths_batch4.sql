-- Batch 4: harden high-impact clinical, pharmacy, billing and workflow SECURITY DEFINER search paths.
alter function public.create_dental_record(uuid, text, text, text) set search_path = pg_catalog, public;
alter function public.create_discharge_insurance_claim(uuid, text, text) set search_path = pg_catalog, public;
alter function public.create_lab_test_catalogue_item(text, text, text, text, text, numeric, numeric, text, numeric, integer) set search_path = pg_catalog, public;
alter function public.create_ophthalmology_exam(uuid, text, text, text, numeric, text, text) set search_path = pg_catalog, public;
alter function public.create_patient_appointment(uuid, timestamptz, text, text) set search_path = pg_catalog, public;
alter function public.create_pharmacy_inventory_item(text, text, text, text, text, text, text, date, integer, integer, numeric) set search_path = pg_catalog, public;
alter function public.create_pharmacy_pos_sale(uuid, uuid, integer) set search_path = pg_catalog, public;
alter function public.create_service_order(uuid, uuid, text, text, numeric, uuid, text, uuid, uuid, uuid, text, text) set search_path = pg_catalog, public;
alter function public.create_staff_shift_assignment(uuid, text, text, timestamptz, timestamptz) set search_path = pg_catalog, public;
alter function public.create_theatre_case(uuid, text, timestamptz, text, text, uuid, uuid, uuid) set search_path = pg_catalog, public;
alter function public.create_transfusion_record(uuid, text, text, text, boolean, uuid) set search_path = pg_catalog, public;
alter function public.create_walk_in_billable_service(uuid, text, integer, text) set search_path = pg_catalog, public;
alter function public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) set search_path = pg_catalog, public;
alter function public.end_video_session(uuid) set search_path = pg_catalog, public;
alter function public.enqueue_external_notification_channels(uuid) set search_path = pg_catalog, public;
