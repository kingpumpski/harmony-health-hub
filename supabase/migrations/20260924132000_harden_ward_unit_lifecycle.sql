BEGIN;

-- Canonical ward configuration is public.ward_units.
-- Direct client writes remain blocked; lifecycle changes go through these
-- server-authoritative RPCs.

CREATE UNIQUE INDEX IF NOT EXISTS ward_units_name_normalized_uniq
  ON public.ward_units (lower(btrim(name)));

CREATE UNIQUE INDEX IF NOT EXISTS ward_units_code_normalized_uniq
  ON public.ward_units (lower(btrim(code)));

CREATE OR REPLACE FUNCTION public.create_ward_unit(
  _name text,
  _code text,
  _specialty text DEFAULT NULL,
  _gender_policy text DEFAULT 'mixed'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
  v_name text := NULLIF(btrim(_name), '');
  v_code text := NULLIF(btrim(_code), '');
  v_specialty text := NULLIF(btrim(_specialty), '');
  v_gender_policy text := lower(NULLIF(btrim(_gender_policy), ''));
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Administrator role required';
  END IF;

  IF v_name IS NULL OR v_code IS NULL THEN
    RAISE EXCEPTION 'Ward name and code are required';
  END IF;

  IF v_gender_policy IS NULL OR v_gender_policy NOT IN ('mixed', 'male', 'female') THEN
    RAISE EXCEPTION 'Invalid gender policy';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.ward_units
    WHERE lower(btrim(name)) = lower(v_name)
       OR lower(btrim(code)) = lower(v_code)
  ) THEN
    RAISE EXCEPTION 'Ward name or code already exists';
  END IF;

  INSERT INTO public.ward_units(name, code, specialty, gender_policy, active)
  VALUES (v_name, v_code, v_specialty, v_gender_policy, true)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_ward_unit(
  _ward_id uuid,
  _name text,
  _code text,
  _specialty text DEFAULT NULL,
  _gender_policy text DEFAULT 'mixed',
  _active boolean DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_name text := NULLIF(btrim(_name), '');
  v_code text := NULLIF(btrim(_code), '');
  v_specialty text := NULLIF(btrim(_specialty), '');
  v_gender_policy text := lower(NULLIF(btrim(_gender_policy), ''));
  v_current_active boolean;
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Administrator role required';
  END IF;

  IF _ward_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.ward_units WHERE id = _ward_id
  ) THEN
    RAISE EXCEPTION 'Ward not found';
  END IF;

  IF v_name IS NULL OR v_code IS NULL THEN
    RAISE EXCEPTION 'Ward name and code are required';
  END IF;

  IF v_gender_policy IS NULL OR v_gender_policy NOT IN ('mixed', 'male', 'female') THEN
    RAISE EXCEPTION 'Invalid gender policy';
  END IF;

  SELECT active
    INTO v_current_active
  FROM public.ward_units
  WHERE id = _ward_id
  FOR UPDATE;

  IF EXISTS (
    SELECT 1
    FROM public.ward_units
    WHERE id <> _ward_id
      AND (
        lower(btrim(name)) = lower(v_name)
        OR lower(btrim(code)) = lower(v_code)
      )
  ) THEN
    RAISE EXCEPTION 'Ward name or code already exists';
  END IF;

  IF v_current_active = true AND _active = false AND EXISTS (
    SELECT 1
    FROM public.ward_beds
    WHERE ward_id = _ward_id
      AND (status = 'occupied' OR patient_id IS NOT NULL OR admission_id IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Cannot deactivate ward with occupied or patient-linked beds';
  END IF;

  UPDATE public.ward_units
  SET name = v_name,
      code = v_code,
      specialty = v_specialty,
      gender_policy = v_gender_policy,
      active = COALESCE(_active, active),
      updated_at = now()
  WHERE id = _ward_id
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_ward_unit_active(
  _ward_id uuid,
  _active boolean
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Administrator role required';
  END IF;

  IF _ward_id IS NULL THEN
    RAISE EXCEPTION 'Ward id is required';
  END IF;

  PERFORM 1
  FROM public.ward_units
  WHERE id = _ward_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ward not found';
  END IF;

  IF _active = false AND EXISTS (
    SELECT 1
    FROM public.ward_beds
    WHERE ward_id = _ward_id
      AND (status = 'occupied' OR patient_id IS NOT NULL OR admission_id IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'Cannot deactivate ward with occupied or patient-linked beds';
  END IF;

  UPDATE public.ward_units
  SET active = _active,
      updated_at = now()
  WHERE id = _ward_id
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_ward_unit(text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_ward_unit(uuid, text, text, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_ward_unit_active(uuid, boolean) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_ward_unit(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ward_unit(uuid, text, text, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_ward_unit_active(uuid, boolean) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON public.ward_units FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.ward_units FROM anon;

COMMIT;
