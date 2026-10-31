-- Establish the nursing-note relation before migrations that add its
-- facility-lineage trigger, query it, create indexes, or install write RPCs.
--
-- This relation was previously assumed to be created by a later clinical
-- schema migration, but no such CREATE TABLE migration exists in the replay
-- history. Keep the definition here so clean local and remote replays have
-- the same dependency order.

CREATE TABLE IF NOT EXISTS public.nursing_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE RESTRICT,
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id uuid REFERENCES public.encounters(id) ON DELETE SET NULL,
  admission_id uuid REFERENCES public.admissions(id) ON DELETE SET NULL,
  author_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  note_type text NOT NULL DEFAULT 'progress',
  note_text text NOT NULL,
  assessment text,
  intervention text,
  evaluation text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT nursing_notes_nonblank_note_text
    CHECK (length(btrim(note_text)) > 0),
  CONSTRAINT nursing_notes_encounter_or_admission_required
    CHECK (encounter_id IS NOT NULL OR admission_id IS NOT NULL)
);

-- Clinical documentation is accessed through the audited, facility-aware
-- SECURITY DEFINER RPCs. Do not expose direct table writes to client roles.
ALTER TABLE public.nursing_notes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nursing_notes FROM PUBLIC, anon, authenticated;
