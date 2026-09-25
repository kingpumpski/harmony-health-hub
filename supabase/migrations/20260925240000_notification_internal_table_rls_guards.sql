-- Explicitly deny direct Data API access to notification control-plane tables.
-- These tables are intentionally server-side and are accessed through authenticated
-- RPCs / Edge Functions. RLS remains enabled as defense in depth; explicit policies
-- make the deny-by-default contract visible to the Supabase security advisor.

do $$
declare
  t text;
begin
  foreach t in array array[
    'notification_deliveries',
    'scheduled_notifications',
    'notification_audit',
    'notification_delivery_logs',
    'notification_provider_credentials',
    'notification_inbound_emails'
  ]
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      'notification_internal_deny_anon', t
    );
    execute format(
      'drop policy if exists %I on public.%I',
      'notification_internal_deny_authenticated', t
    );

    execute format(
      'create policy %I on public.%I for all to anon using (false) with check (false)',
      'notification_internal_deny_anon', t
    );
    execute format(
      'create policy %I on public.%I for all to authenticated using (false) with check (false)',
      'notification_internal_deny_authenticated', t
    );
  end loop;
end $$;
