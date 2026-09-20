select ok(
  to_regprocedure('public.claim_notification_queue(integer)') is not null,
  'atomic notification queue claim function exists'
);

select ok(
  has_function_privilege('service_role', 'public.claim_notification_queue(integer)', 'EXECUTE'),
  'service role can execute queue claim function'
);

select ok(
  not has_function_privilege('anon', 'public.claim_notification_queue(integer)', 'EXECUTE'),
  'anon cannot execute queue claim function'
);

select ok(
  not has_function_privilege('authenticated', 'public.claim_notification_queue(integer)', 'EXECUTE'),
  'authenticated cannot execute queue claim function'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'notifications'
      and indexname = 'notifications_source_queue_id_uq'
  ),
  'notification delivery has an idempotency index'
);
