
-- ===== Notifications =====
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_role app_role,            -- broadcast to all users with this role
  recipient_user_id UUID,             -- or to a specific user (e.g. patient)
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  severity TEXT NOT NULL DEFAULT 'info',  -- info | success | warning | critical
  category TEXT,                          -- lab | payment | appointment | encounter | triage | prescription | telemedicine | other
  link TEXT,
  related_patient_id UUID,
  related_entity_id UUID,
  metadata JSONB DEFAULT '{}'::jsonb,
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (recipient_role IS NOT NULL OR recipient_user_id IS NOT NULL)
);

CREATE INDEX idx_notif_role_unread ON public.notifications(recipient_role) WHERE is_read = false;
CREATE INDEX idx_notif_user_unread ON public.notifications(recipient_user_id) WHERE is_read = false;
CREATE INDEX idx_notif_created ON public.notifications(created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users see notifications for their role or themselves"
  ON public.notifications FOR SELECT TO authenticated
  USING (
    recipient_user_id = auth.uid()
    OR (recipient_role IS NOT NULL AND public.has_role(auth.uid(), recipient_role))
  );

CREATE POLICY "staff insert notifications"
  ON public.notifications FOR INSERT TO authenticated
  WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'accountant') OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "users mark their own notifications read"
  ON public.notifications FOR UPDATE TO authenticated
  USING (
    recipient_user_id = auth.uid()
    OR (recipient_role IS NOT NULL AND public.has_role(auth.uid(), recipient_role))
  );

-- ===== Department queue (cross-dashboard workflow board) =====
CREATE TABLE public.department_queues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  department TEXT NOT NULL,    -- triage | consultation | laboratory | radiology | pharmacy | nursing | billing | telemedicine | fertility
  status TEXT NOT NULL DEFAULT 'waiting',   -- waiting | in_progress | blocked_payment | completed | cancelled
  priority TEXT NOT NULL DEFAULT 'routine', -- critical | urgent | routine
  reason TEXT,
  related_encounter_id UUID,
  related_invoice_id UUID,
  payment_required BOOLEAN NOT NULL DEFAULT false,
  payment_satisfied BOOLEAN NOT NULL DEFAULT false,
  created_by UUID,
  assigned_to UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);
CREATE INDEX idx_dq_dept_status ON public.department_queues(department, status);
CREATE INDEX idx_dq_priority ON public.department_queues(priority);

ALTER TABLE public.department_queues ENABLE ROW LEVEL SECURITY;

CREATE POLICY "staff read queues"
  ON public.department_queues FOR SELECT TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'accountant'));

CREATE POLICY "staff manage queues"
  ON public.department_queues FOR ALL TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'accountant'))
  WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'accountant'));

CREATE POLICY "patient reads own queue"
  ON public.department_queues FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM patients p WHERE p.id = department_queues.patient_id AND p.user_id = auth.uid()));

CREATE TRIGGER trg_dq_touch BEFORE UPDATE ON public.department_queues
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ===== Patient code auto-generation =====
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS insurance_expiry DATE,
  ADD COLUMN IF NOT EXISTS insurance_group_number TEXT;

ALTER TABLE public.patients ALTER COLUMN patient_code DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.generate_patient_code()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
DECLARE
  next_seq INTEGER;
  ymd TEXT;
BEGIN
  IF NEW.patient_code IS NULL OR NEW.patient_code = '' THEN
    ymd := to_char(now(), 'YYYYMMDD');
    SELECT COUNT(*) + 1 INTO next_seq
    FROM public.patients
    WHERE patient_code LIKE 'MED-' || ymd || '-%';
    NEW.patient_code := 'MED-' || ymd || '-' || lpad(next_seq::text, 4, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_patient_code ON public.patients;
CREATE TRIGGER trg_patient_code BEFORE INSERT ON public.patients
  FOR EACH ROW EXECUTE FUNCTION public.generate_patient_code();

-- ===== Attach existing invoice totals trigger to payments =====
DROP TRIGGER IF EXISTS trg_refresh_invoice_totals ON public.payments;
CREATE TRIGGER trg_refresh_invoice_totals
  AFTER INSERT OR UPDATE OR DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.refresh_invoice_totals();

-- ===== Realtime publication =====
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
ALTER TABLE public.department_queues REPLICA IDENTITY FULL;
ALTER TABLE public.appointments REPLICA IDENTITY FULL;
ALTER TABLE public.lab_results REPLICA IDENTITY FULL;
ALTER TABLE public.prescriptions REPLICA IDENTITY FULL;
ALTER TABLE public.payments REPLICA IDENTITY FULL;
ALTER TABLE public.video_sessions REPLICA IDENTITY FULL;
ALTER TABLE public.vital_signs REPLICA IDENTITY FULL;

ALTER PUBLICATION supabase_realtime ADD TABLE
  public.notifications,
  public.department_queues,
  public.appointments,
  public.lab_results,
  public.prescriptions,
  public.payments,
  public.video_sessions,
  public.vital_signs;
