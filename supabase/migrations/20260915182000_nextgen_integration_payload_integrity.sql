-- Enforce cryptographic payload integrity at the durable interoperability boundary.
-- The application runtime may use a lightweight in-memory fingerprint for duplicate
-- detection, but persisted transport records must carry a SHA-256 digest computed
-- by PostgreSQL so client code cannot forge the integrity value.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public.set_platform_integration_payload_hash()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.payload_hash := encode(
    digest(convert_to(NEW.payload::text, 'UTF8'), 'sha256'),
    'hex'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS platform_integration_payload_hash_trigger
  ON public.platform_integration_messages;

CREATE TRIGGER platform_integration_payload_hash_trigger
BEFORE INSERT OR UPDATE OF payload
ON public.platform_integration_messages
FOR EACH ROW
EXECUTE FUNCTION public.set_platform_integration_payload_hash();

COMMENT ON FUNCTION public.set_platform_integration_payload_hash() IS
  'Computes the authoritative SHA-256 payload digest for the interoperability delivery ledger.';

-- The authoritative value is always a lowercase SHA-256 hex digest.
ALTER TABLE public.platform_integration_messages
  DROP CONSTRAINT IF EXISTS platform_integration_messages_payload_hash_format;

ALTER TABLE public.platform_integration_messages
  ADD CONSTRAINT platform_integration_messages_payload_hash_format
  CHECK (payload_hash ~ '^[0-9a-f]{64}$');
