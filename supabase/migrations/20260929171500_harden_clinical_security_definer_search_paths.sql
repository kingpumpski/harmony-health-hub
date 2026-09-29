-- Harden high-impact clinical SECURITY DEFINER RPCs against search_path shadowing.
alter function public.approve_lab_result(uuid)
  set search_path = pg_catalog, public;

alter function public.complete_imaging_order(uuid, text, text)
  set search_path = pg_catalog, public;

alter function public.confirm_pharmacy_dispense(uuid)
  set search_path = pg_catalog, public;
