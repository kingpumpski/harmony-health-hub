-- Expand the source-format contract for governed legacy clinical migration uploads.
-- Historical rows remain staged and are not promoted by this constraint change.
ALTER TABLE public.data_migration_batches
  DROP CONSTRAINT IF EXISTS data_migration_batches_source_format_check;

ALTER TABLE public.data_migration_batches
  ADD CONSTRAINT data_migration_batches_source_format_check
  CHECK (source_format IN ('csv', 'xlsx', 'json', 'xml', 'hl7', 'other'));
