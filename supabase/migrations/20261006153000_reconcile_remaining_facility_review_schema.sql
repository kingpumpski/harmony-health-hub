-- Reconcile the remaining facility-attribution review projection with the canonical ward schema.
-- The legacy review projection referenced wards.name/ward_type, but public.wards now exposes
-- department/active. Keep the review read server-authoritative and administrator-only.

CREATE OR REPLACE FUNCTION public.list_unresolved_remaining_clinical_facility_records(_limit integer DEFAULT 500)
RETURNS TABLE(entity_type text,entity_id uuid,patient_id uuid,created_at timestamptz,metadata jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NOT (public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('it_admin'::public.app_role)) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;

  RETURN QUERY
  SELECT 'wards',w.id,NULL::uuid,w.created_at,
         jsonb_build_object('department',w.department,'active',w.active)
  FROM public.wards w WHERE w.facility_id IS NULL
  UNION ALL SELECT 'beds',b.id,b.patient_id,b.created_at,
    jsonb_build_object('bed_number',b.bed_number,'ward_id',b.ward_id)
  FROM public.beds b WHERE b.facility_id IS NULL
  UNION ALL SELECT 'anesthetic_assessments',a.id,a.patient_id,a.created_at,
    jsonb_build_object('status',a.status,'encounter_id',a.encounter_id)
  FROM public.anesthetic_assessments a WHERE a.facility_id IS NULL
  UNION ALL SELECT 'billing_overrides',b.id,b.patient_id,b.created_at,
    jsonb_build_object('department',b.department,'reason',b.reason,'service_order_id',b.service_order_id)
  FROM public.billing_overrides b WHERE b.facility_id IS NULL
  UNION ALL SELECT 'dental_records',d.id,d.patient_id,d.created_at,
    jsonb_build_object('encounter_id',d.encounter_id)
  FROM public.dental_records d WHERE d.facility_id IS NULL
  UNION ALL SELECT 'inpatient_reviews',i.id,i.patient_id,i.created_at,
    jsonb_build_object('admission_id',i.admission_id,'review_type',i.review_type)
  FROM public.inpatient_reviews i WHERE i.facility_id IS NULL
  UNION ALL SELECT 'meal_orders',m.id,m.patient_id,m.created_at,
    jsonb_build_object('meal_plan_id',m.meal_plan_id,'meal_type',m.meal_type,'status',m.status)
  FROM public.meal_orders m WHERE m.facility_id IS NULL
  UNION ALL SELECT 'meal_plans',m.id,m.patient_id,m.created_at,
    jsonb_build_object('plan_type',m.plan_type,'active',m.active)
  FROM public.meal_plans m WHERE m.facility_id IS NULL
  UNION ALL SELECT 'ophthalmology_exams',o.id,o.patient_id,o.created_at,
    jsonb_build_object('status',o.status,'performed_by',o.performed_by)
  FROM public.ophthalmology_exams o WHERE o.facility_id IS NULL
  UNION ALL SELECT 'outside_lab_documents',o.id,o.patient_id,o.created_at,
    jsonb_build_object('document_type',o.document_type,'title',o.title)
  FROM public.outside_lab_documents o WHERE o.facility_id IS NULL
  UNION ALL SELECT 'patient_account_credits',p.id,p.patient_id,p.created_at,
    jsonb_build_object('entry_type',p.entry_type,'amount',p.amount,'invoice_id',p.invoice_id)
  FROM public.patient_account_credits p WHERE p.facility_id IS NULL
  UNION ALL SELECT 'patient_visit_authorizations',p.id,p.patient_id,p.created_at,
    jsonb_build_object('payer_name',p.payer_name,'coverage_type',p.coverage_type,'appointment_id',p.appointment_id)
  FROM public.patient_visit_authorizations p WHERE p.facility_id IS NULL
  UNION ALL SELECT 'video_sessions',v.id,v.patient_id,v.created_at,
    jsonb_build_object('appointment_id',v.appointment_id,'service_order_id',v.service_order_id,'status',v.status)
  FROM public.video_sessions v WHERE v.facility_id IS NULL
  LIMIT greatest(1,least(coalesce(_limit,500),1000));
END;
$function$;

REVOKE ALL ON FUNCTION public.list_unresolved_remaining_clinical_facility_records(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_unresolved_remaining_clinical_facility_records(integer) TO authenticated;
