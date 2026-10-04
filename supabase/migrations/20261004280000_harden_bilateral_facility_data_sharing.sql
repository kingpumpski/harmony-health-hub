BEGIN;

CREATE OR REPLACE FUNCTION public.create_facility_data_sharing_agreement(
  _facility_a_id uuid,
  _facility_b_id uuid,
  _purpose text,
  _effective_from timestamptz,
  _effective_to timestamptz,
  _scopes text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_id uuid;
  v_scope text;
  v_effective_from timestamptz := COALESCE(_effective_from, pg_catalog.now());
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'system_superuser'::public.app_role) THEN
    RAISE EXCEPTION 'System Superuser access required';
  END IF;
  IF _facility_a_id = _facility_b_id THEN RAISE EXCEPTION 'Facilities must be different'; END IF;
  IF COALESCE(pg_catalog.btrim(_purpose),'') = '' THEN RAISE EXCEPTION 'Purpose is required'; END IF;
  IF COALESCE(pg_catalog.array_length(_scopes,1),0)=0 THEN RAISE EXCEPTION 'At least one data-sharing scope is required'; END IF;
  IF _effective_to IS NOT NULL AND _effective_to <= v_effective_from THEN
    RAISE EXCEPTION 'Effective end must be after effective start';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.healthcare_facilities WHERE id=_facility_a_id AND is_active)
     OR NOT EXISTS(SELECT 1 FROM public.healthcare_facilities WHERE id=_facility_b_id AND is_active) THEN
    RAISE EXCEPTION 'Both facilities must be active';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.facility_data_sharing_agreements a
    WHERE a.status IN ('pending','active')
      AND LEAST(a.facility_a_id,a.facility_b_id)=LEAST(_facility_a_id,_facility_b_id)
      AND GREATEST(a.facility_a_id,a.facility_b_id)=GREATEST(_facility_a_id,_facility_b_id)
      AND COALESCE(a.effective_to,'infinity'::timestamptz) > v_effective_from
      AND COALESCE(_effective_to,'infinity'::timestamptz) > a.effective_from
  ) THEN
    RAISE EXCEPTION 'A pending or active agreement already covers these facilities for the requested period';
  END IF;

  FOREACH v_scope IN ARRAY _scopes LOOP
    IF v_scope NOT IN ('patient_read','clinical_read','encounter_read','diagnosis_read','lab_read','imaging_read','medication_read','billing_read','document_read','care_coordination') THEN
      RAISE EXCEPTION 'Unsupported data-sharing scope: %',v_scope;
    END IF;
  END LOOP;

  INSERT INTO public.facility_data_sharing_agreements(
    facility_a_id,facility_b_id,purpose,effective_from,effective_to,created_by
  ) VALUES (
    _facility_a_id,_facility_b_id,_purpose,v_effective_from,_effective_to,auth.uid()
  ) RETURNING id INTO v_id;

  FOREACH v_scope IN ARRAY _scopes LOOP
    INSERT INTO public.facility_data_sharing_agreement_scopes(agreement_id,scope_code)
    VALUES(v_id,v_scope);
  END LOOP;

  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(auth.uid(),'facility_data_sharing_agreement_created','administration','facility_data_sharing_agreement',v_id,'info',
    jsonb_build_object('facility_a_id',_facility_a_id,'facility_b_id',_facility_b_id,'purpose',_purpose,'scopes',_scopes));

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_facility_data_sharing_agreement(_agreement_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_a uuid;
  v_b uuid;
  v_facility uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT facility_a_id,facility_b_id INTO v_a,v_b
  FROM public.facility_data_sharing_agreements WHERE id=_agreement_id FOR UPDATE;
  IF v_a IS NULL THEN RAISE EXCEPTION 'Agreement not found'; END IF;

  IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'it_admin'::public.app_role)) THEN
    RAISE EXCEPTION 'Facility administrator access required';
  END IF;
  v_facility:=public.current_user_facility_id();
  IF v_facility IS NULL OR v_facility NOT IN (v_a,v_b) THEN
    RAISE EXCEPTION 'Agreement is outside your facility';
  END IF;

  IF v_facility=v_a THEN
    UPDATE public.facility_data_sharing_agreements
    SET facility_a_approved_by=auth.uid(),facility_a_approved_at=pg_catalog.now(),updated_at=pg_catalog.now()
    WHERE id=_agreement_id;
  ELSE
    UPDATE public.facility_data_sharing_agreements
    SET facility_b_approved_by=auth.uid(),facility_b_approved_at=pg_catalog.now(),updated_at=pg_catalog.now()
    WHERE id=_agreement_id;
  END IF;

  UPDATE public.facility_data_sharing_agreements
  SET status='active',updated_at=pg_catalog.now()
  WHERE id=_agreement_id
    AND facility_a_approved_by IS NOT NULL
    AND facility_b_approved_by IS NOT NULL
    AND status NOT IN ('revoked','expired')
    AND effective_from <= pg_catalog.now()
    AND (effective_to IS NULL OR effective_to > pg_catalog.now());

  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(auth.uid(),'facility_data_sharing_agreement_approved','administration','facility_data_sharing_agreement',_agreement_id,'info',
    jsonb_build_object('facility_id',v_facility));
END;
$function$;

CREATE OR REPLACE FUNCTION public.revoke_facility_data_sharing_agreement(_agreement_id uuid,_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_a uuid;
  v_b uuid;
  v_facility uuid;
BEGIN
  IF auth.uid() IS NULL OR COALESCE(pg_catalog.btrim(_reason),'')='' THEN
    RAISE EXCEPTION 'Authentication and revocation reason are required';
  END IF;
  SELECT facility_a_id,facility_b_id INTO v_a,v_b
  FROM public.facility_data_sharing_agreements WHERE id=_agreement_id FOR UPDATE;
  IF v_a IS NULL THEN RAISE EXCEPTION 'Agreement not found'; END IF;

  IF public.has_role(auth.uid(),'system_superuser'::public.app_role) THEN
    NULL;
  ELSE
    IF NOT (public.has_role(auth.uid(),'admin'::public.app_role) OR public.has_role(auth.uid(),'it_admin'::public.app_role)) THEN
      RAISE EXCEPTION 'Facility administrator access required';
    END IF;
    v_facility:=public.current_user_facility_id();
    IF v_facility IS NULL OR v_facility NOT IN (v_a,v_b) THEN
      RAISE EXCEPTION 'Agreement is outside your facility';
    END IF;
  END IF;

  UPDATE public.facility_data_sharing_agreements
  SET status='revoked',revoked_by=auth.uid(),revoked_at=pg_catalog.now(),updated_at=pg_catalog.now(),
      metadata=metadata || pg_catalog.jsonb_build_object('revocation_reason',_reason)
  WHERE id=_agreement_id;
  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(auth.uid(),'facility_data_sharing_agreement_revoked','administration','facility_data_sharing_agreement',_agreement_id,'warning',
    pg_catalog.jsonb_build_object('reason',_reason));
END;
$function$;

REVOKE ALL ON FUNCTION public.create_facility_data_sharing_agreement(uuid,uuid,text,timestamptz,timestamptz,text[]) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.approve_facility_data_sharing_agreement(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.revoke_facility_data_sharing_agreement(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_facility_data_sharing_agreement(uuid,uuid,text,timestamptz,timestamptz,text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_facility_data_sharing_agreement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_facility_data_sharing_agreement(uuid,text) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;