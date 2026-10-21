-- Harden legacy nursing care-plan SECURITY DEFINER RPCs without changing
-- their signatures, authorization checks, grants, or workflow behavior.
ALTER FUNCTION public.create_nursing_care_plan(uuid, text, text, text, text, uuid, uuid)
  SET search_path = pg_catalog, public;

ALTER FUNCTION public.review_nursing_care_plan(uuid, text, text)
  SET search_path = pg_catalog, public;
