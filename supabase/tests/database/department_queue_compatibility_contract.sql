DO $$
BEGIN
  ASSERT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='department_queues'
      AND column_name='queued_at' AND data_type='timestamp with time zone'
      AND is_nullable='NO' AND column_default IS NOT NULL
  ), 'department_queues.queued_at must be a non-null timestamp with a default';
  ASSERT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='department_queues'
      AND column_name='service_order_id' AND data_type='uuid'
  ), 'department_queues.service_order_id compatibility column missing';
  ASSERT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='department_queues'
      AND column_name='claimed_by' AND data_type='uuid'
  ), 'department_queues.claimed_by compatibility column missing';
  ASSERT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='department_queues'
      AND column_name='claimed_at' AND data_type='timestamp with time zone'
  ), 'department_queues.claimed_at compatibility column missing';
  ASSERT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='department_queues'
      AND indexname='idx_department_queues_work'
      AND indexdef ILIKE '%(department, status, queued_at)%'
  ), 'department queue work index must be created after queued_at exists';
  ASSERT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class source_table ON source_table.oid=c.conrelid
    JOIN pg_namespace source_schema ON source_schema.oid=source_table.relnamespace
    JOIN pg_class target_table ON target_table.oid=c.confrelid
    JOIN pg_namespace target_schema ON target_schema.oid=target_table.relnamespace
    WHERE c.conname='department_queues_service_order_fk'
      AND c.contype='f'
      AND source_schema.nspname='public'
      AND source_table.relname='department_queues'
      AND target_schema.nspname='public'
      AND target_table.relname='service_orders'
  ), 'department queue service-order foreign key missing';
  ASSERT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='department_queues'
      AND indexname='uq_department_queues_service_order'
      AND indexdef ILIKE '%UNIQUE INDEX%'
  ), 'department queue service-order uniqueness guard missing';
  ASSERT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname='department_queues' AND c.relrowsecurity
  ), 'department_queues must retain RLS';
END $$;
