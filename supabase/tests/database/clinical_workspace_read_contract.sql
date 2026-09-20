-- Contract tests for clinical workspace read hardening.
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef('public.get_imaging_workspace(integer)'::regprocedure) INTO v_def;
  IF v_def IS NULL OR position('auth.uid() IS NULL' IN v_def)=0 THEN
    RAISE EXCEPTION 'Imaging workspace must require authentication';
  END IF;
  IF position('radiologist' IN v_def)=0 OR position('radiology_technician' IN v_def)=0 THEN
    RAISE EXCEPTION 'Imaging workspace role boundary missing';
  END IF;

  SELECT pg_get_functiondef('public.get_laboratory_workspace(integer)'::regprocedure) INTO v_def;
  IF position('patient_code' IN v_def)=0 OR position('email' IN v_def)>0 THEN
    RAISE EXCEPTION 'Laboratory workspace patient projection is not least privilege';
  END IF;

  SELECT pg_get_functiondef('public.get_pharmacy_workspace(integer)'::regprocedure) INTO v_def;
  IF position('auth.uid() IS NULL' IN v_def)=0 OR position('pharmacist' IN v_def)=0 THEN
    RAISE EXCEPTION 'Pharmacy workspace authorization boundary missing';
  END IF;
END $$;

DO $$
DECLARE v_public_acl text;
BEGIN
  SELECT pg_get_functiondef('public.get_imaging_workspace(integer)'::regprocedure) INTO v_public_acl;
  IF position('REVOKE' IN upper(v_public_acl)) > 0 THEN
    RAISE EXCEPTION 'ACL statements are not part of function definition; inspect migration';
  END IF;
END $$;
