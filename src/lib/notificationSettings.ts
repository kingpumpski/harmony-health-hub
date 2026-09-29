import { supabase } from '@/integrations/supabase/client';
import { reportsDb } from '@/lib/reportsDb';

export interface FacilityNotificationConfig {
  facility_id: string;
  environment: 'sandbox' | 'test' | 'production';
  enabled: boolean;
  default_locale: string;
  default_timezone: string;
  quiet_hours_start: string;
  quiet_hours_end: string;
  enabled_channels: Record<string, boolean>;
  rollout_percent: number;
  kill_switch: boolean;
  onboarding_status: 'not_started' | 'in_progress' | 'sandbox_ready' | 'verification_pending' | 'production_ready' | 'suspended';
  branding: Record<string, unknown>;
  provider_defaults: Record<string, unknown>;
  delivery_policy: Record<string, unknown>;
  webhook_policy: Record<string, unknown>;
  compliance_policy: Record<string, unknown>;
  operational_contacts: Record<string, unknown>;
  deployment_secret_namespace: string | null;
  production_approved_at: string | null;
  production_approved_by: string | null;
}

export interface NotificationProviderSecretRequirement {
  id: string;
  provider: string;
  channel: 'email' | 'sms' | 'push' | 'whatsapp' | 'voice';
  secret_name: string;
  environment: 'all' | 'sandbox' | 'test' | 'production';
  required: boolean;
  description: string;
  secret_reference_example: string | null;
}

export async function getFacilityNotificationConfig(facilityId: string): Promise<FacilityNotificationConfig | null> {
  const { data, error } = await reportsDb
    .from('facility_notification_config')
    .select('facility_id,environment,enabled,default_locale,default_timezone,quiet_hours_start,quiet_hours_end,enabled_channels,rollout_percent,kill_switch,onboarding_status,branding,provider_defaults,delivery_policy,webhook_policy,compliance_policy,operational_contacts,deployment_secret_namespace,production_approved_at,production_approved_by')
    .eq('facility_id', facilityId)
    .maybeSingle();
  if (error) throw new Error(error.message);
  return (data ?? null) as FacilityNotificationConfig | null;
}

export async function listNotificationProviderSecretRequirements(): Promise<NotificationProviderSecretRequirement[]> {
  const { data, error } = await reportsDb
    .from('notification_provider_secret_requirements')
    .select('id,provider,channel,secret_name,environment,required,description,secret_reference_example')
    .order('channel')
    .order('provider')
    .order('secret_name');
  if (error) throw new Error(error.message);
  return (data ?? []) as NotificationProviderSecretRequirement[];
}

export async function initializeFacilityNotificationOnboarding(facilityId: string): Promise<FacilityNotificationConfig> {
  const { data, error } = await reportsDb.rpc('initialize_facility_notification_onboarding', { _facility_id: facilityId });
  if (error) throw new Error(error.message);
  if (!data) throw new Error('Notification onboarding returned no configuration.');
  return data as FacilityNotificationConfig;
}

export async function configureFacilityNotificationProvider(input: {
  facilityId: string;
  channel: 'email' | 'sms' | 'push' | 'whatsapp' | 'voice';
  provider: string;
  environment: 'sandbox' | 'test' | 'production';
  secretReference?: string | null;
  senderIdentity?: string | null;
  accountReference?: string | null;
}) {
  const { data, error } = await reportsDb.rpc('set_facility_notification_provider', {
    _facility_id: input.facilityId,
    _channel: input.channel,
    _provider: input.provider,
    _environment: input.environment,
    _secret_reference: input.secretReference ?? null,
    _sender_identity: input.senderIdentity ?? null,
    _account_reference: input.accountReference ?? null,
    _metadata: {},
  });
  if (error) throw new Error(error.message);
  return data;
}

export async function configureEmailProvider(input: {
  facilityId: string;
  environment: 'sandbox' | 'test' | 'production';
  provider: 'resend' | 'smtp';
  credentials: Record<string, unknown>;
  test?: boolean;
  testRecipient?: string | null;
  priority?: number;
  isPrimary?: boolean;
}) {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) throw new Error('Authenticated session required.');
  const response = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/notification-provider-config`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error ?? 'Email provider configuration failed.');
  return result;
}
