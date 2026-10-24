-- Ensure diagnostic staff role labels exist before policies and RPCs cast them to app_role.
-- Enum additions are committed in their own migration before later functions use them.
DO $diagnostic_roles$
BEGIN
  IF to_regtype('public.app_role') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public' AND t.typname='app_role' AND e.enumlabel='radiologist'
    ) THEN
      ALTER TYPE public.app_role ADD VALUE 'radiologist';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public' AND t.typname='app_role' AND e.enumlabel='radiology_technician'
    ) THEN
      ALTER TYPE public.app_role ADD VALUE 'radiology_technician';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public' AND t.typname='app_role' AND e.enumlabel='ophthalmologist'
    ) THEN
      ALTER TYPE public.app_role ADD VALUE 'ophthalmologist';
    END IF;
  END IF;
END
$diagnostic_roles$;
