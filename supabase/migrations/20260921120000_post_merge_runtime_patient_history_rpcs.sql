-- Post-merge runtime read boundaries for Patient Hub history.
CREATE OR REPLACE FUNCTION public.get_patient_appointments(_patient_id uuid, _limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_limit integer:=greatest(1,least(coalesce(_limit,100),100));
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Appointment history access is not permitted'; END IF;
 IF NOT EXISTS (SELECT 1 FROM patients p WHERE p.id=_patient_id AND p.status <> 'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.scheduled_at DESC) FROM (
  SELECT a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,a.attending_officer_id,a.treatment_status,a.treatment_notes
  FROM appointments a WHERE a.patient_id=_patient_id ORDER BY a.scheduled_at DESC LIMIT v_limit
 ) x),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_patient_appointments(uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_appointments(uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_patient_invoices(_patient_id uuid, _limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_limit integer:=greatest(1,least(coalesce(_limit,100),100));
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Billing history access is not permitted'; END IF;
 IF NOT EXISTS (SELECT 1 FROM patients p WHERE p.id=_patient_id AND p.status <> 'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 RETURN COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
  SELECT i.id,i.patient_id,i.invoice_number,i.total_amount,i.status,i.created_at
  FROM invoices i WHERE i.patient_id=_patient_id ORDER BY i.created_at DESC LIMIT v_limit
 ) x),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_patient_invoices(uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_invoices(uuid,integer) TO authenticated;