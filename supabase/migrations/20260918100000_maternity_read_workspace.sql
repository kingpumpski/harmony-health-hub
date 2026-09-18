CREATE OR REPLACE FUNCTION public.get_maternity_workspace(
  _limit INTEGER DEFAULT 200,
  _episode_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_episodes JSONB;
  v_observations JSONB;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR
    has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR
    has_role(auth.uid(),'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Maternity access is not permitted';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC), '[]'::jsonb)
    INTO v_episodes
  FROM (
    SELECT id, patient_id, gravida, para, lmp, edd, risk_level, status, notes, created_at
    FROM public.maternity_episodes
    WHERE (_episode_id IS NULL OR id = _episode_id)
    ORDER BY created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(_limit,200),1),500)
  ) e;

  SELECT COALESCE(jsonb_agg(to_jsonb(o) ORDER BY o.observed_at DESC), '[]'::jsonb)
    INTO v_observations
  FROM (
    SELECT id, episode_id, observed_at, blood_pressure, pulse, temperature,
           fetal_heart_rate, contractions_per_10_min, cervical_dilation_cm,
           effacement_percent, station, membrane_status, notes
    FROM public.maternity_observations
    WHERE _episode_id IS NOT NULL AND episode_id = _episode_id
    ORDER BY observed_at DESC
    LIMIT 20
  ) o;

  RETURN jsonb_build_object('episodes', v_episodes, 'observations', v_observations);
END;
$$;

REVOKE ALL ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) TO authenticated;