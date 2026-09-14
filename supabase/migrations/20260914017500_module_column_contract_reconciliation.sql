-- Reconcile canonical application-facing column names with the production schema.
-- Additive only; preserve existing data and compatibility aliases where legacy names exist.

ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS appointment_date timestamptz;
UPDATE public.appointments SET appointment_date = scheduled_at WHERE appointment_date IS NULL;
ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS provider_id uuid;
UPDATE public.appointments SET provider_id = practitioner_id WHERE provider_id IS NULL;

ALTER TABLE public.diagnoses ADD COLUMN IF NOT EXISTS patient_id uuid;
UPDATE public.diagnoses d SET patient_id = e.patient_id FROM public.encounters e WHERE e.id = d.encounter_id AND d.patient_id IS NULL;
ALTER TABLE public.diagnoses ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS provider_id uuid;
UPDATE public.encounters SET provider_id = practitioner_id WHERE provider_id IS NULL;
ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS chief_complaint text;
ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS history_of_present_illness text;
ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS assessment text;
ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS plan text;
ALTER TABLE public.encounters ADD COLUMN IF NOT EXISTS started_at timestamptz;
UPDATE public.encounters SET started_at = created_at WHERE started_at IS NULL;

ALTER TABLE public.invoice_items ADD COLUMN IF NOT EXISTS patient_id uuid;
UPDATE public.invoice_items i SET patient_id = inv.patient_id FROM public.invoices inv WHERE inv.id = i.invoice_id AND i.patient_id IS NULL;
ALTER TABLE public.invoice_items ADD COLUMN IF NOT EXISTS total_price numeric(12,2);
UPDATE public.invoice_items SET total_price = amount WHERE total_price IS NULL;

ALTER TABLE public.lab_results ADD COLUMN IF NOT EXISTS patient_id uuid;
UPDATE public.lab_results lr SET patient_id = lo.patient_id FROM public.lab_orders lo WHERE lo.id = lr.lab_order_id AND lr.patient_id IS NULL;
ALTER TABLE public.lab_results ADD COLUMN IF NOT EXISTS result text;
UPDATE public.lab_results SET result = result_data::text WHERE result IS NULL;

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS read_at timestamptz;
UPDATE public.notifications SET read_at = CASE WHEN is_read THEN created_at ELSE NULL END WHERE read_at IS NULL;

ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS payment_method text;
UPDATE public.payments SET payment_method = method WHERE payment_method IS NULL;
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'completed';
ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS paid_at timestamptz;
UPDATE public.payments SET paid_at = created_at WHERE paid_at IS NULL;

ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS medication_name text;
UPDATE public.prescriptions SET medication_name = medication WHERE medication_name IS NULL;
ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS route text;
ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.report_generation_items ADD COLUMN IF NOT EXISTS report_definition_id uuid;
UPDATE public.report_generation_items SET report_definition_id = report_id WHERE report_definition_id IS NULL;
ALTER TABLE public.report_generation_items ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.report_generation_runs ADD COLUMN IF NOT EXISTS reporting_period_start date;
UPDATE public.report_generation_runs SET reporting_period_start = period_start WHERE reporting_period_start IS NULL;
ALTER TABLE public.report_generation_runs ADD COLUMN IF NOT EXISTS reporting_period_end date;
UPDATE public.report_generation_runs SET reporting_period_end = period_end WHERE reporting_period_end IS NULL;
ALTER TABLE public.report_generation_runs ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.report_submissions ADD COLUMN IF NOT EXISTS report_definition_id uuid;
UPDATE public.report_submissions SET report_definition_id = report_id WHERE report_definition_id IS NULL;
ALTER TABLE public.report_submissions ADD COLUMN IF NOT EXISTS reporting_period_start date;
UPDATE public.report_submissions SET reporting_period_start = period_start WHERE reporting_period_start IS NULL;
ALTER TABLE public.report_submissions ADD COLUMN IF NOT EXISTS reporting_period_end date;
UPDATE public.report_submissions SET reporting_period_end = period_end WHERE reporting_period_end IS NULL;

ALTER TABLE public.vital_signs ADD COLUMN IF NOT EXISTS encounter_id uuid;
ALTER TABLE public.vital_signs ADD COLUMN IF NOT EXISTS entered_by uuid;
UPDATE public.vital_signs SET entered_by = recorded_by WHERE entered_by IS NULL;
ALTER TABLE public.vital_signs ADD COLUMN IF NOT EXISTS weight numeric;
UPDATE public.vital_signs SET weight = weight_kg WHERE weight IS NULL;
ALTER TABLE public.vital_signs ADD COLUMN IF NOT EXISTS height numeric;
UPDATE public.vital_signs SET height = height_cm WHERE height IS NULL;
ALTER TABLE public.vital_signs ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
UPDATE public.vital_signs SET created_at = recorded_at WHERE created_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_appointments_provider_id ON public.appointments(provider_id);
CREATE INDEX IF NOT EXISTS idx_appointments_appointment_date ON public.appointments(appointment_date);
CREATE INDEX IF NOT EXISTS idx_diagnoses_patient_id ON public.diagnoses(patient_id);
CREATE INDEX IF NOT EXISTS idx_encounters_provider_id ON public.encounters(provider_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_patient_id ON public.invoice_items(patient_id);
CREATE INDEX IF NOT EXISTS idx_lab_results_patient_id ON public.lab_results(patient_id);
CREATE INDEX IF NOT EXISTS idx_vital_signs_encounter_id ON public.vital_signs(encounter_id);

NOTIFY pgrst, 'reload schema';
