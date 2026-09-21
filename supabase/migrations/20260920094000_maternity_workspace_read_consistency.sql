-- Maternity workspace read consistency hardening.
-- Forward-only: preserves the existing workspace contract while preventing
-- orphaned/cross-context maternity reads.

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
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    has_role(auth.uid(),'admin') OR
    has_role(auth.uid(),'practitioner') OR
    has_role(auth.uid(),'nurse') OR
    has_role(auth.uid(),'midwife') OR
    has_role(auth.uid(),'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Maternity access is not permitted';
  END IF;

  IF _episode_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.maternity_episodes me
    JOIN public.patients p ON p.id = me.patient_id
    WHERE me.id = _episode_id
  ) THEN
    RAISE EXCEPTION 'Maternity episode not found';
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC), '[]'::jsonb)
  INTO v_episodes
  FROM (
    SELECT me.id, me.patient_id, me.gravida, me.para, me.lmp, me.edd,
           me.risk_level, me.status, me.notes, me.created_at
    FROM public.maternity_episodes me
    JOIN public.patients p ON p.id = me.patient_id
    WHERE (_episode_id IS NULL OR me.id = _episode_id)
    ORDER BY me.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(_limit,200),1),500)
  ) e;

  SELECT COALESCE(jsonb_agg(to_jsonb(o) ORDER BY o.observed_at DESC), '[]'::jsonb)
  INTO v_observations
  FROM (
    SELECT mo.id, mo.episode_id, mo.observed_at, mo.blood_pressure,
           mo.pulse, mo.temperature, mo.fetal_heart_rate,
           mo.contractions_per_10_min, mo.cervical_dilation_cm,
           mo.effacement_percent, mo.station, mo.membrane_status, mo.notes
    FROM public.maternity_observations mo
    JOIN public.maternity_episodes me ON me.id = mo.episode_id
    JOIN public.patients p ON p.id = me.patient_id
    WHERE _episode_id IS NOT NULL AND mo.episode_id = _episode_id
    ORDER BY mo.observed_at DESC
    LIMIT 20
  ) o;

  RETURN jsonb_build_object(
    'episodes', v_episodes,
    'observations', v_observations
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_maternity_workspace(INTEGER,UUID) TO authenticated;
