-- Batch 3: harden remaining high-impact workflow SECURITY DEFINER search paths.
alter function public.acknowledge_nursing_handover(uuid) set search_path = pg_catalog, public;
alter function public.claim_appointment(uuid) set search_path = pg_catalog, public;
alter function public.collect_lab_sample(uuid) set search_path = pg_catalog, public;
alter function public.complete_service_order(uuid) set search_path = pg_catalog, public;
alter function public.confirm_pharmacy_pos_sale(uuid) set search_path = pg_catalog, public;
alter function public.create_appointment_workflow(uuid, timestamptz, text, text) set search_path = pg_catalog, public;
alter function public.create_appointment_workflow(uuid, timestamptz, text, text, text, uuid) set search_path = pg_catalog, public;
alter function public.create_care_transition_workflow(uuid, text, text, text, boolean, boolean, date, text) set search_path = pg_catalog, public;
alter function public.create_emergency_case(uuid, text, text, text, uuid) set search_path = pg_catalog, public;
alter function public.create_fertility_cycle_workflow(uuid, text, text, date, text) set search_path = pg_catalog, public;
alter function public.create_maternity_episode_workflow(uuid, integer, integer, date, date, text, text, text) set search_path = pg_catalog, public;
alter function public.create_nursing_care_plan(uuid, text, text, text, text, uuid, uuid) set search_path = pg_catalog, public;
alter function public.create_nursing_shift_handover(uuid, text, text, text, text, boolean, uuid) set search_path = pg_catalog, public;
