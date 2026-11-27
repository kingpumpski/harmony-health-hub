import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const migration = (name) => readFile(path.join(root, 'supabase', 'migrations', name), 'utf8');
const [canonical, lifecycle, divergent, dashboard, hardening] = await Promise.all([
  migration('20260911004959_e283cf8c-f6e8-4347-b4c0-689d591d33e4.sql'),
  migration('20260911233000_phase2_service_order_payment_gating.sql'),
  migration('20260912162000_hims_workflow_completion.sql'),
  migration('20260929200000_role_dashboard_kpi_cleanup.sql'),
  migration('20260916100000_harden_service_order_override_and_release_contract.sql'),
]);

assert.match(canonical, /CREATE TABLE public\.service_orders\s*\([\s\S]*?\bstatus\s+TEXT\s+NOT NULL/i,
  'The original service-order table must establish status as the canonical state field');
assert.match(lifecycle, /ALTER TABLE public\.service_orders\s+ADD COLUMN IF NOT EXISTS invoice_item_id/i,
  'The payment lifecycle migration must extend, not recreate, the canonical service-order table');
assert.match(lifecycle, /ADD CONSTRAINT service_orders_status_check\s+CHECK\s*\(status IN \('pending_payment_approval','released','in_progress','completed','cancelled'\)\)/i,
  'The canonical lifecycle state vocabulary must remain explicit');
const divergentServiceOrders = divergent.match(/CREATE TABLE IF NOT EXISTS public\.service_orders\s*\(([\s\S]*?)\n\);/i)?.[1];
assert.ok(divergentServiceOrders, 'The divergent service_orders declaration must remain present');
assert.match(divergentServiceOrders, /payment_status\s+TEXT/i, 'The divergent definition must expose payment_status');
assert.match(divergentServiceOrders, /fulfillment_status\s+TEXT/i, 'The divergent definition must expose fulfillment_status');
assert.doesNotMatch(divergentServiceOrders, /\bstatus\s+TEXT/i,
  'The divergent HIMS definition must not be mistaken for the canonical status-based model');
assert.match(divergent, /ON public\.service_orders\s*\(department,\s*fulfillment_status,\s*priority,\s*created_at\)/i,
  'The divergent migration index dependency must remain documented and detectable');
assert.match(divergent, /NEW\.fulfillment_status/i,
  'The divergent trigger dependency must remain documented and detectable');
assert.match(hardening, /service_orders\.status|NEW\.status|OLD\.status/i,
  'The later release/override hardening must continue to use the canonical status field');
assert.match(dashboard, /FROM public\.service_orders WHERE status IN/i,
  'The dashboard must continue to consume the canonical status field');
assert.match(divergent, /SET search_path\s*=\s*public/i,
  'The divergent migration search_path exposure must remain visible for security review');
assert.match(divergent, /to_jsonb\(OLD\)[\s\S]*to_jsonb\(NEW\)/i,
  'Full-row patient audit capture must remain visible for privacy/data-minimization review');

console.log('[migration-20260912162000-service-order-conflict] PASS: canonical status model, divergent state fields, downstream dependencies, public search_path, and full-row patient audit risks are pinned; historical migration remains blocked pending forward reconciliation.');
