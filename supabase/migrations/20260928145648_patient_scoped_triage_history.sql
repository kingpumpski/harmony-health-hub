-- Patient-scoped triage history read boundary.
-- The RPC intentionally returns no rows for NULL patient IDs and never falls back to a global query.
CREATE OR REPLACE FUNCTION public.get_patient_triage_history(
  _patient_id uuid,
  _limit integer DEFAULT 100
)
RETURNS TABLE (
  id uuid,
  patient_id uuid,
  recorded_at timestamptz,
  temperature numeric,
  systolic integer,
  diastolic integer,
  bmi numeric,
  oxygen_saturation numeric
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.patient_id,
    t.created_at AS recorded_at,
    t.temperature,
    t.systolic,
    t.diastolic,
    t.bmi,
    t.oxygen_saturation
  FROM public.triage_assessments AS t
  WHERE _patient_id IS NOT NULL
    AND t.patient_id = _patient_id
  ORDER BY t.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(_limit, 100), 1), 500);
$$;

REVOKE ALL ON FUNCTION public.get_patient_triage_history(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_patient_triage_history(uuid, integer) TO authenticated;
