-- Refresh PostgREST's function schema cache after the patient-history RPC
-- security/signature repairs. This prevents stale RPC metadata from surfacing
-- as Data API method/signature errors after migrations.
NOTIFY pgrst, 'reload schema';
