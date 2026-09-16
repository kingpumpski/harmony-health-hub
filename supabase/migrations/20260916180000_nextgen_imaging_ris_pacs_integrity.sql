-- Next-generation imaging/RIS/PACS integrity boundary.
-- Extends the canonical imaging_orders workflow without creating a parallel imaging system.
-- Acquisition metadata is transport/reconciliation state; clinical reporting remains human-authoritative.

ALTER TABLE public.imaging_orders
  ADD COLUMN IF NOT EXISTS accession_number TEXT,
  ADD COLUMN IF NOT EXISTS dicom_study_uid TEXT,
  ADD COLUMN IF NOT EXISTS pacs_reference TEXT,
  ADD COLUMN IF NOT EXISTS image_count INTEGER NOT NULL DEFAULT 0 CHECK (image_count >= 0),
  ADD COLUMN IF NOT EXISTS acquisition_status TEXT NOT NULL DEFAULT 'not_started'
    CHECK (acquisition_status IN ('not_started','acquiring','acquired','failed','cancelled')),
  ADD COLUMN IF NOT EXISTS acquired_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acquired_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS report_finalized_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS report_finalized_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS uq_imaging_orders_dicom_study_uid
  ON public.imaging_orders(dicom_study_uid)
  WHERE dicom_study_uid IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_imaging_orders_accession_number
  ON public.imaging_orders(accession_number)
  WHERE accession_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_imaging_orders_acquisition_status
  ON public.imaging_orders(acquisition_status, updated_at DESC);

CREATE OR REPLACE FUNCTION public.record_imaging_acquisition(
  _imaging_order_id UUID,
  _accession_number TEXT,
  _dicom_study_uid TEXT,
  _image_count INTEGER DEFAULT 0,
  _pacs_reference TEXT DEFAULT NULL
)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.imaging_orders;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.is_clinical_staff(v_uid) THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;
  IF _imaging_order_id IS NULL THEN
    RAISE EXCEPTION 'Imaging order is required';
  END IF;
  IF NULLIF(trim(COALESCE(_accession_number,'')), '') IS NULL THEN
    RAISE EXCEPTION 'Accession number is required';
  END IF;
  IF NULLIF(trim(COALESCE(_dicom_study_uid,'')), '') IS NULL THEN
    RAISE EXCEPTION 'DICOM study UID is required';
  END IF;
  IF COALESCE(_image_count,0) < 0 THEN
    RAISE EXCEPTION 'Image count cannot be negative';
  END IF;

  SELECT * INTO v_order
    FROM public.imaging_orders
   WHERE id = _imaging_order_id
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
  IF v_order.status <> 'in_progress' THEN
    RAISE EXCEPTION 'Imaging acquisition requires an in-progress order';
  END IF;
  IF v_order.acquisition_status IN ('acquired','cancelled') THEN
    RAISE EXCEPTION 'Imaging acquisition is already closed';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.imaging_orders
     WHERE dicom_study_uid = trim(_dicom_study_uid)
       AND id <> v_order.id
  ) THEN
    RAISE EXCEPTION 'DICOM study UID is already associated with another imaging order';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.imaging_orders
     WHERE accession_number = trim(_accession_number)
       AND id <> v_order.id
  ) THEN
    RAISE EXCEPTION 'Accession number is already associated with another imaging order';
  END IF;

  UPDATE public.imaging_orders
     SET accession_number = trim(_accession_number),
         dicom_study_uid = trim(_dicom_study_uid),
         pacs_reference = NULLIF(trim(COALESCE(_pacs_reference,'')),''),
         image_count = COALESCE(_image_count,0),
         acquisition_status = 'acquired',
         acquired_at = COALESCE(acquired_at, now()),
         acquired_by = v_uid,
         updated_at = now()
   WHERE id = v_order.id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_imaging_report(
  _imaging_order_id UUID,
  _report TEXT,
  _impression TEXT
)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.imaging_orders;
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT public.is_clinical_staff(v_uid) THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;
  IF NULLIF(trim(COALESCE(_report,'')),'') IS NULL
     AND NULLIF(trim(COALESCE(_impression,'')),'') IS NULL THEN
    RAISE EXCEPTION 'A report or impression is required before finalization';
  END IF;

  SELECT * INTO v_order
    FROM public.imaging_orders
   WHERE id = _imaging_order_id
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
  IF v_order.status <> 'in_progress' THEN
    RAISE EXCEPTION 'Only an in-progress imaging order can be finalized';
  END IF;
  IF v_order.acquisition_status <> 'acquired' THEN
    RAISE EXCEPTION 'Imaging acquisition must be reconciled before report finalization';
  END IF;
  IF v_order.report_finalized_at IS NOT NULL THEN
    RAISE EXCEPTION 'Imaging report is already finalized';
  END IF;

  UPDATE public.imaging_orders
     SET report = NULLIF(trim(COALESCE(_report,'')),''),
         impression = NULLIF(trim(COALESCE(_impression,'')),''),
         status = 'completed',
         report_finalized_by = v_uid,
         report_finalized_at = now(),
         updated_at = now()
   WHERE id = v_order.id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.record_imaging_acquisition(UUID,TEXT,TEXT,INTEGER,TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.finalize_imaging_report(UUID,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_imaging_acquisition(UUID,TEXT,TEXT,INTEGER,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.finalize_imaging_report(UUID,TEXT,TEXT) TO authenticated;

REVOKE INSERT, UPDATE, DELETE ON TABLE public.imaging_orders FROM authenticated;

DROP TRIGGER IF EXISTS trg_audit_imaging_orders_changes ON public.imaging_orders;
CREATE TRIGGER trg_audit_imaging_orders_changes
AFTER INSERT OR UPDATE OR DELETE ON public.imaging_orders
FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_record_change();

COMMENT ON FUNCTION public.record_imaging_acquisition(UUID,TEXT,TEXT,INTEGER,TEXT) IS
  'Reconciles RIS/PACS acquisition metadata into the canonical imaging order; it never finalizes a clinical report.';
COMMENT ON FUNCTION public.finalize_imaging_report(UUID,TEXT,TEXT) IS
  'Human-authoritative imaging report finalization after acquisition reconciliation.';
