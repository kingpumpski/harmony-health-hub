-- Align role-specific dashboard KPIs with operational workflow ownership.
-- Keeps radiologist interpretation separate from technician acquisition and
-- replaces pharmacist medication-administration counts with inventory expiry watch.
CREATE OR REPLACE FUNCTION public.get_role_dashboard_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_cards jsonb := '[]'::jsonb;
  v_today_start timestamptz := date_trunc('day', now());
  v_today_end timestamptz := date_trunc('day', now()) + interval '1 day';
  v_patient_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT ur.role::text INTO v_role
  FROM public.user_roles ur
  WHERE ur.user_id = v_uid
    AND ur.role IN ('admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin')
  ORDER BY ur.created_at ASC, ur.role::text ASC
  LIMIT 1;

  IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;

  IF v_role = 'patient' THEN
    SELECT p.id INTO v_patient_id FROM public.patients p WHERE p.user_id=v_uid ORDER BY p.created_at DESC LIMIT 1;
    IF v_patient_id IS NULL THEN
      RETURN jsonb_build_object('role',v_role,'cards',jsonb_build_array(
        jsonb_build_object('key','appointments','label','Upcoming appointments','value',0,'href','/appointments','description','No linked patient profile found'),
        jsonb_build_object('key','notifications','label','Unread notifications','value',0,'href','/notifications','description','No notifications')
      ));
    END IF;
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','appointments','label','Upcoming appointments','value',count(*),'href','/appointments','description','Scheduled or active visits') x FROM public.appointments a WHERE a.patient_id=v_patient_id AND a.scheduled_at>=now() AND a.status NOT IN ('cancelled','no_show')
      UNION ALL SELECT jsonb_build_object('key','unpaid','label','Unpaid invoices','value',count(*),'href','/billing','description','Invoices with an outstanding balance') FROM public.invoices i WHERE i.patient_id=v_patient_id AND COALESCE(i.outstanding_amount,0)>0
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Notifications awaiting review') FROM public.notifications n WHERE n.recipient_user_id=v_uid AND NOT n.is_read
      UNION ALL SELECT jsonb_build_object('key','active_care','label','Active care records','value',count(*),'href','/patient-portal','description','Open encounters or active admissions') FROM public.encounters e WHERE e.patient_id=v_patient_id AND e.status NOT IN ('completed','cancelled')
    ) q;
    RETURN jsonb_build_object('role',v_role,'cards',COALESCE(v_cards,'[]'::jsonb));
  END IF;

  IF v_role='admin' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','staff','label','Staff profiles','value',count(*),'href','/admin/users','description','Registered staff profiles') x FROM public.profiles
      UNION ALL SELECT jsonb_build_object('key','appointments','label','Today appointments','value',count(*),'href','/appointments','description','Appointments scheduled today') FROM public.appointments WHERE scheduled_at>=v_today_start AND scheduled_at<v_today_end AND status NOT IN ('cancelled','no_show')
      UNION ALL SELECT jsonb_build_object('key','critical','label','Critical alerts','value',count(*),'href','/notifications','description','Unread critical notifications') FROM public.notifications WHERE NOT is_read AND severity='critical'
      UNION ALL SELECT jsonb_build_object('key','service_orders','label','Open service orders','value',count(*),'href','/department-queue','description','Service work awaiting completion') FROM public.service_orders WHERE status IN ('pending_payment_approval','released','in_progress')
      UNION ALL SELECT jsonb_build_object('key','unpaid','label','Unpaid invoices','value',count(*),'href','/billing','description','Invoices with an outstanding balance') FROM public.invoices WHERE COALESCE(outstanding_amount,0)>0
      UNION ALL SELECT jsonb_build_object('key','claims','label','Claims needing action','value',count(*),'href','/insurance-claims','description','Claims not fully paid or rejected') FROM public.insurance_claims WHERE status IN ('draft','submitted','approved','partially_paid')
    ) q;
  ELSIF v_role='practitioner' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','appointments','label','Today appointments','value',count(*),'href','/appointments','description','Active appointments today') x FROM public.appointments WHERE scheduled_at>=v_today_start AND scheduled_at<v_today_end AND status NOT IN ('cancelled','no_show')
      UNION ALL SELECT jsonb_build_object('key','lab','label','Laboratory queue','value',count(*),'href','/laboratory','description','Orders awaiting completion') FROM public.lab_orders WHERE status IN ('ordered','collected','in_progress')
      UNION ALL SELECT jsonb_build_object('key','imaging','label','Radiology queue','value',count(*),'href','/radiology','description','Imaging orders not completed') FROM public.imaging_orders WHERE status<>'completed'
      UNION ALL SELECT jsonb_build_object('key','inpatients','label','Active inpatients','value',count(*),'href','/inpatient','description','Currently admitted patients') FROM public.admissions WHERE status='admitted'
      UNION ALL SELECT jsonb_build_object('key','critical','label','Critical alerts','value',count(*),'href','/notifications','description','Unread critical notifications') FROM public.notifications WHERE NOT is_read AND severity='critical'
      UNION ALL SELECT jsonb_build_object('key','services','label','Open services','value',count(*),'href','/department-queue','description','Service orders awaiting completion') FROM public.service_orders WHERE status IN ('released','in_progress')
    ) q;
  ELSIF v_role IN ('nurse','midwife','specialist_nurse') THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','admissions','label','Active admissions','value',count(*),'href','/inpatient','description','Patients currently admitted') x FROM public.admissions WHERE status='admitted'
      UNION ALL SELECT jsonb_build_object('key','medications','label','Due medications','value',count(*),'href','/medications','description','Scheduled medication administrations not completed') FROM public.medication_administrations WHERE status='scheduled' AND scheduled_at BETWEEN now()-interval '30 minutes' AND now()+interval '2 hours'
      UNION ALL SELECT jsonb_build_object('key','handovers','label','Unacknowledged handovers','value',count(*),'href','/nursing-handover','description','Shift handovers awaiting acknowledgement') FROM public.nursing_shift_handovers WHERE acknowledged_at IS NULL
      UNION ALL SELECT jsonb_build_object('key','triage','label','Critical triage','value',count(*),'href','/vitals','description','Critical triage assessments') FROM public.triage_assessments WHERE is_critical
      UNION ALL SELECT jsonb_build_object('key','queue','label','Department queue','value',count(*),'href','/department-queue','description','Waiting or active departmental work') FROM public.department_queues WHERE status IN ('waiting','in_progress')
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Unread workflow events') FROM public.notifications WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT is_read
    ) q;
  ELSIF v_role='lab_technician' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','queue','label','Laboratory queue','value',count(*),'href','/laboratory','description','Orders awaiting processing') x FROM public.lab_orders WHERE status IN ('ordered','collected','in_progress')
      UNION ALL SELECT jsonb_build_object('key','urgent','label','Urgent tests','value',count(*),'href','/laboratory','description','Urgent or STAT orders not completed') FROM public.lab_orders WHERE priority IN ('urgent','stat') AND status NOT IN ('approved','completed','cancelled')
      UNION ALL SELECT jsonb_build_object('key','approval','label','Results awaiting approval','value',count(*),'href','/lab-results','description','Entered results awaiting approval') FROM public.lab_results WHERE status IN ('entered','pending_review')
      UNION ALL SELECT jsonb_build_object('key','services','label','Department queue','value',count(*),'href','/department-queue','description','Laboratory service orders') FROM public.department_queues WHERE department='laboratory' AND status IN ('waiting','in_progress')
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Unread workflow events') FROM public.notifications n WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT n.is_read
    ) q;
  ELSIF v_role='radiologist' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','ready','label','Ready for interpretation','value',count(*),'href','/radiology','description','Released or queued studies awaiting radiologist interpretation') x FROM public.imaging_orders WHERE status IN ('released','queued')
      UNION ALL SELECT jsonb_build_object('key','urgent','label','Urgent / STAT','value',count(*),'href','/radiology','description','Urgent studies awaiting radiologist attention') FROM public.imaging_orders WHERE priority IN ('urgent','stat') AND status IN ('released','queued')
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Unread workflow events') FROM public.notifications WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT is_read
    ) q;
  ELSIF v_role='radiology_technician' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','ready','label','Ready for acquisition','value',count(*),'href','/radiology','description','Released or queued studies awaiting acquisition') x FROM public.imaging_orders WHERE status IN ('released','queued')
      UNION ALL SELECT jsonb_build_object('key','progress','label','Acquisition in progress','value',count(*),'href','/radiology','description','Studies currently being acquired') FROM public.imaging_orders WHERE status='in_progress'
      UNION ALL SELECT jsonb_build_object('key','urgent','label','Urgent / STAT','value',count(*),'href','/radiology','description','Urgent studies requiring acquisition attention') FROM public.imaging_orders WHERE priority IN ('urgent','stat') AND status IN ('released','queued','in_progress')
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Unread workflow events') FROM public.notifications WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT is_read
    ) q;
  ELSIF v_role='pharmacist' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','dispensing','label','Dispensing queue','value',count(*),'href','/pharmacy','description','Medication plans awaiting preparation or dispensing') x FROM public.pharmacy_dispensing_plans WHERE status IN ('pending','prepared')
      UNION ALL SELECT jsonb_build_object('key','inventory','label','Inventory alerts','value',count(*),'href','/stock-alerts','description','Items at or below reorder level') FROM public.pharmacy_inventory WHERE active AND stock_quantity<=COALESCE(reorder_level,0)
      UNION ALL SELECT jsonb_build_object('key','expiry','label','Expiry watch','value',count(*),'href','/stock-alerts','description','Active stock expiring within 30 days') FROM public.pharmacy_inventory WHERE active AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE+30
      UNION ALL SELECT jsonb_build_object('key','queue','label','Department queue','value',count(*),'href','/department-queue','description','Pharmacy service orders') FROM public.department_queues WHERE department='pharmacy' AND status IN ('waiting','in_progress')
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Unread workflow events') FROM public.notifications WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT is_read
    ) q;
  ELSIF v_role='accountant' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','approvals','label','Payment approvals','value',count(*),'href','/accounts-approvals','description','Items awaiting accounts action') x FROM public.service_orders WHERE status='pending_payment_approval'
      UNION ALL SELECT jsonb_build_object('key','unpaid','label','Unpaid invoices','value',count(*),'href','/billing','description','Invoices with outstanding balances') FROM public.invoices WHERE COALESCE(outstanding_amount,0)>0
      UNION ALL SELECT jsonb_build_object('key','claims','label','Claims needing action','value',count(*),'href','/insurance-claims','description','Claims awaiting financial action') FROM public.insurance_claims WHERE status IN ('draft','submitted','approved','partially_paid')
      UNION ALL SELECT jsonb_build_object('key','queue','label','Finance queue','value',count(*),'href','/finance','description','Financial workflow items') FROM public.service_orders WHERE status IN ('pending_payment_approval','released')
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Unread workflow events') FROM public.notifications WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT n.is_read
    ) q;
  ELSIF v_role='front_desk' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','appointments','label','Today appointments','value',count(*),'href','/appointments','description','Appointments scheduled today') x FROM public.appointments WHERE scheduled_at>=v_today_start AND scheduled_at<v_today_end AND status NOT IN ('cancelled','no_show')
      UNION ALL SELECT jsonb_build_object('key','registration','label','Active patients','value',count(*),'href','/patients','description','Active patient records') FROM public.patients WHERE status='active'
      UNION ALL SELECT jsonb_build_object('key','queue','label','Department queue','value',count(*),'href','/department-queue','description','Patients waiting across departments') FROM public.department_queues WHERE status='waiting'
      UNION ALL SELECT jsonb_build_object('key','billing','label','Unpaid invoices','value',count(*),'href','/billing','description','Accounts requiring payment handling') FROM public.invoices WHERE COALESCE(outstanding_amount,0)>0
      UNION ALL SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Unread workflow events') FROM public.notifications WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT n.is_read
    ) q;
  ELSIF v_role='canteen' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','meals_due','label','Meals due today','value',count(*),'href','/orders','description','Meal orders scheduled today and not delivered') x FROM public.meal_orders WHERE scheduled_for>=v_today_start AND scheduled_for<v_today_end AND status<>'delivered'
      UNION ALL SELECT jsonb_build_object('key','pending','label','Pending deliveries','value',count(*),'href','/orders','description','Meal orders awaiting delivery') FROM public.meal_orders WHERE status='pending'
      UNION ALL SELECT jsonb_build_object('key','plans','label','Active diet plans','value',count(*),'href','/dietary-plans','description','Active patient dietary plans') FROM public.meal_plans WHERE active
      UNION ALL SELECT jsonb_build_object('key','restrictions','label','Plans with restrictions','value',count(*),'href','/dietary-plans','description','Active plans with dietary restrictions') FROM public.meal_plans WHERE active AND NULLIF(trim(restrictions),'') IS NOT NULL
    ) q;
  ELSIF v_role='it_admin' THEN
    SELECT jsonb_agg(x ORDER BY x->>'key') INTO v_cards FROM (
      SELECT jsonb_build_object('key','notifications','label','Unread notifications','value',count(*),'href','/notifications','description','Operational alerts awaiting review') x FROM public.notifications WHERE (recipient_user_id=v_uid OR recipient_role=v_role::public.app_role) AND NOT is_read
      UNION ALL SELECT jsonb_build_object('key','offline','label','Offline sync queue','value',count(*),'href','/admin/offline-sync','description','Queued synchronization events') FROM public.sync_queue WHERE NOT synced
      UNION ALL SELECT jsonb_build_object('key','audit','label','Recent audit events','value',count(*),'href','/admin/logs','description','System audit events in the last 24 hours') FROM public.system_audit_log WHERE created_at>=now()-interval '24 hours'
    ) q;
  ELSE
    RAISE EXCEPTION 'Unsupported dashboard role';
  END IF;

  RETURN jsonb_build_object('role',v_role,'cards',COALESCE(v_cards,'[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.get_role_dashboard_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary() TO authenticated;
NOTIFY pgrst, 'reload schema';
