export type NotificationChannel = 'in_app' | 'email' | 'sms' | 'push' | 'whatsapp' | 'voice';
export type NotificationPriority = 'critical' | 'high' | 'medium' | 'low';
export type NotificationStatus = 'queued' | 'sent' | 'delivered' | 'read' | 'clicked' | 'failed' | 'bounced' | 'unsubscribed';

export interface NotificationEventEnvelope<T = Record<string, unknown>> {
  event_name: string;
  event_id: string;
  user_id: string;
  tenant_id?: string | null;
  occurred_at: string;
  priority: NotificationPriority;
  locale?: string;
  timezone?: string;
  template_key: string;
  channels?: NotificationChannel[];
  idempotency_key?: string;
  payload: T;
}

export interface DeliveryResult {
  channel: NotificationChannel;
  provider?: string;
  providerMessageId?: string;
  status: Extract<NotificationStatus, 'sent' | 'delivered' | 'failed' | 'bounced' | 'unsubscribed'>;
  errorCode?: string;
  errorMessage?: string;
  latencyMs: number;
  retryable: boolean;
}

export interface ChannelAdapter {
  readonly channel: NotificationChannel;
  send(input: {
    recipient: { userId: string; email?: string; phone?: string; pushToken?: string };
    subject?: string;
    body: string;
    metadata?: Record<string, unknown>;
  }): Promise<DeliveryResult>;
}