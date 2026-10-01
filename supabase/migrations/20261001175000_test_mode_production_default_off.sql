-- Production-safe default: test mode must be disabled unless explicitly enabled
-- in a dedicated non-production test environment.
update public.hms_test_runtime
set enabled = false, updated_at = now()
where id = true;
