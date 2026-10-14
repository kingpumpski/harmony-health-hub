-- Keep specialty roles within the established clinical-staff helper boundary.
-- Reuse the current function definition so SECURITY DEFINER/search_path/grants are preserved.
DO $migration$
DECLARE
  v_definition text;
  v_old_roles text := '''front_desk'',''canteen''';
  v_new_roles text := '''front_desk'',''canteen'',''physiotherapist'',''ophthalmologist'',''dentist'',''dietician''';
BEGIN
  SELECT pg_catalog.pg_get_functiondef(
    'public.current_user_is_clinical_staff()'::pg_catalog.regprocedure
  ) INTO v_definition;

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'Required clinical staff helper is missing';
  END IF;

  IF pg_catalog.strpos(v_definition, v_old_roles) = 0 THEN
    RAISE EXCEPTION 'Clinical staff helper differs from the expected role list; review before applying';
  END IF;

  v_definition := pg_catalog.replace(v_definition, v_old_roles, v_new_roles);
  EXECUTE v_definition;
END;
$migration$;
