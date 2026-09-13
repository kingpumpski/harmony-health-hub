-- Maternity workflow hardening: browser clients must use audited, role-scoped RPCs.
CREATE OR REPLACE FUNCTION public.create_maternity_episode_workflow(
  _patient_id UUID,
  _gravida INTEGER DEFAULT NULL,
  _para INTEGER DEFAULT NULL,
  _lmp DATE DEFAULT NULL,
  _edd DATE DEFAULT NULL,
  _risk_level TEXT DEFAULT 'routine',
  _status TEXT DEFAULT 'antenatal',
  _notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Maternity episode creation is not permitted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _gravida IS NOT NULL AND _gravida < 0 THEN RAISE EXCEPTION 'Gravida cannot be negative'; END IF;
  IF _para IS NOT NULL AND _para < 0 THEN RAISE EXCEPTION 'Para cannot be negative'; END IF;
  IF _risk_level NOT IN ('routine','high','critical') THEN RAISE EXCEPTION 'Invalid maternity risk level'; END IF;
  IF _status NOT IN ('antenatal','labour','postpartum') THEN RAISE EXCEPTION 'Invalid maternity episode status'; END IF;

  INSERT INTO maternity_episodes(patient_id, gravida, para, lmp, edd, risk_level, status, notes, created_by)
  VALUES (_patient_id, _gravida, _para, _lmp, _edd, _risk_level, _status, NULLIF(btrim(_notes),''), auth.uid())
  RETURNING id INTO v_id;

  PERFORM record_system_audit('maternity_episode_created','maternity','maternity_episode',v_id,'info',jsonb_build_object('patient_id',_patient_id,'risk_level',_risk_level,'status',_status));
  RETURN jsonb_build_object('episode_id',v_id,'status',_status);
END; $$;

CREATE OR REPLACE FUNCTION public.record_maternity_observation_workflow(
  _episode_id UUID,
  _blood_pressure TEXT DEFAULT NULL,
  _pulse INTEGER DEFAULT NULL,
  _temperature NUMERIC DEFAULT NULL,
  _fetal_heart_rate INTEGER DEFAULT NULL,
  _contractions_per_10_min INTEGER DEFAULT NULL,
  _cervical_dilation_cm NUMERIC DEFAULT NULL,
  _effacement_percent INTEGER DEFAULT NULL,
  _station TEXT DEFAULT NULL,
  _membrane_status TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID; v_patient_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Maternity observation recording is not permitted';
  END IF;
  SELECT patient_id INTO v_patient_id FROM maternity_episodes WHERE id = _episode_id AND status <> 'completed' AND status <> 'cancelled';
  IF v_patient_id IS NULL THEN RAISE EXCEPTION 'Active maternity episode not found'; END IF;
  IF _pulse IS NOT NULL AND _pulse < 0 THEN RAISE EXCEPTION 'Pulse cannot be negative'; END IF;
  IF _fetal_heart_rate IS NOT NULL AND _fetal_heart_rate < 0 THEN RAISE EXCEPTION 'Fetal heart rate cannot be negative'; END IF;
  IF _effacement_percent IS NOT NULL AND (_effacement_percent < 0 OR _effacement_percent > 100) THEN RAISE EXCEPTION 'Effacement must be between 0 and 100'; END IF;
  IF _cervical_dilation_cm IS NOT NULL AND (_cervical_dilation_cm < 0 OR _cervical_dilation_cm > 10) THEN RAISE EXCEPTION 'Cervical dilation must be between 0 and 10 cm'; END IF;

  INSERT INTO maternity_observations(episode_id, blood_pressure, pulse, temperature, fetal_heart_rate, contractions_per_10_min, cervical_dilation_cm, effacement_percent, station, membrane_status, notes, recorded_by)
  VALUES (_episode_id, NULLIF(btrim(_blood_pressure),''), _pulse, _temperature, _fetal_heart_rate, _contractions_per_10_min, _cervical_dilation_cm, _effacement_percent, NULLIF(btrim(_station),''), NULLIF(btrim(_membrane_status),''), NULLIF(btrim(_notes),''), auth.uid())
  RETURNING id INTO v_id;

  PERFORM record_system_audit('maternity_observation_recorded','maternity','maternity_observation',v_id,'info',jsonb_build_object('patient_id',v_patient_id,'episode_id',_episode_id));
  RETURN jsonb_build_object('observation_id',v_id,'episode_id',_episode_id);
END; $$;

REVOKE ALL ON FUNCTION public.create_maternity_episode_workflow(UUID,INTEGER,INTEGER,DATE,DATE,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_maternity_observation_workflow(UUID,TEXT,INTEGER,NUMERIC,INTEGER,INTEGER,NUMERIC,INTEGER,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_maternity_episode_workflow(UUID,INTEGER,INTEGER,DATE,DATE,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_maternity_observation_workflow(UUID,TEXT,INTEGER,NUMERIC,INTEGER,INTEGER,NUMERIC,INTEGER,TEXT,TEXT,TEXT) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.maternity_episodes FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.maternity_observations FROM authenticated;
GRANT SELECT ON public.maternity_episodes TO authenticated;
GRANT SELECT ON public.maternity_observations TO authenticated;
