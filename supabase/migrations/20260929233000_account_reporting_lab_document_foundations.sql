BEGIN;

CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  theme text NOT NULL DEFAULT 'system',
  locale text NOT NULL DEFAULT 'en',
  timezone text NOT NULL DEFAULT 'Africa/Accra',
  date_format text NOT NULL DEFAULT 'medium',
  time_format text NOT NULL DEFAULT '24h',
  density text NOT NULL DEFAULT 'comfortable',
  notification_sound_enabled boolean NOT NULL DEFAULT true,
  email_notifications_enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "user preferences self read" ON public.user_preferences;
CREATE POLICY "user preferences self read" ON public.user_preferences FOR SELECT TO authenticated USING ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS "user preferences self insert" ON public.user_preferences;
CREATE POLICY "user preferences self insert" ON public.user_preferences FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS "user preferences self update" ON public.user_preferences;
CREATE POLICY "user preferences self update" ON public.user_preferences FOR UPDATE TO authenticated USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);
REVOKE ALL ON public.user_preferences FROM anon;
GRANT SELECT, INSERT, UPDATE ON public.user_preferences TO authenticated;

CREATE TABLE IF NOT EXISTS public.user_document_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name text NOT NULL,
  professional_title text,
  signature_data text NOT NULL,
  signature_hash text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS user_document_signatures_active_uq ON public.user_document_signatures(user_id) WHERE is_active;
ALTER TABLE public.user_document_signatures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "signature owner read" ON public.user_document_signatures;
CREATE POLICY "signature owner read" ON public.user_document_signatures FOR SELECT TO authenticated USING ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS "signature owner insert" ON public.user_document_signatures;
CREATE POLICY "signature owner insert" ON public.user_document_signatures FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS "signature owner update" ON public.user_document_signatures;
CREATE POLICY "signature owner update" ON public.user_document_signatures FOR UPDATE TO authenticated USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);
REVOKE ALL ON public.user_document_signatures FROM anon;
GRANT SELECT, INSERT, UPDATE ON public.user_document_signatures TO authenticated;

ALTER TABLE public.report_definitions ADD COLUMN IF NOT EXISTS audience_roles text[] NOT NULL DEFAULT '{}';
ALTER TABLE public.report_definitions ADD COLUMN IF NOT EXISTS department_code text;
ALTER TABLE public.report_definitions ADD COLUMN IF NOT EXISTS report_scope text NOT NULL DEFAULT 'facility';
CREATE INDEX IF NOT EXISTS idx_report_definitions_audience_roles ON public.report_definitions USING gin(audience_roles);
CREATE INDEX IF NOT EXISTS idx_report_definitions_department_code ON public.report_definitions(department_code);

ALTER TABLE public.lab_test_catalogue ADD COLUMN IF NOT EXISTS parameters jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE public.lab_results ADD COLUMN IF NOT EXISTS parameter_results jsonb NOT NULL DEFAULT '{}'::jsonb;
CREATE INDEX IF NOT EXISTS idx_lab_orders_patient_status ON public.lab_orders(patient_id,status,created_at DESC);

COMMIT;