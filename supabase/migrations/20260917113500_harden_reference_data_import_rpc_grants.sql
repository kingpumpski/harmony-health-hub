-- Keep reference-data migration endpoints authenticated-only at the database privilege layer.
-- Function bodies additionally require the administrator role.
REVOKE EXECUTE ON FUNCTION public.create_data_migration_batch(TEXT,TEXT,TEXT,TEXT,TEXT,INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_data_migration_batch(TEXT,TEXT,TEXT,TEXT,TEXT,INTEGER) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_data_migration_batch(TEXT,TEXT,TEXT,TEXT,TEXT,INTEGER) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.stage_data_migration_rows(UUID,JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.stage_data_migration_rows(UUID,JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.stage_data_migration_rows(UUID,JSONB) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.import_stg_diagnoses(TEXT,TEXT,JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.import_stg_diagnoses(TEXT,TEXT,JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.import_stg_diagnoses(TEXT,TEXT,JSONB) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.import_service_tariffs(TEXT,JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.import_service_tariffs(TEXT,JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION public.import_service_tariffs(TEXT,JSONB) TO authenticated;
