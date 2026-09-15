export type CommunicationChannel = 'in_app' | 'sms' | 'email' | 'voice' | 'push' | 'portal';

export interface CommunicationPreferences {
  preferredLanguage: string;
  preferredChannels: CommunicationChannel[];
  quietHours?: { start?: string; end?: string; timezone?: string };
  appointmentReminders: boolean;
  medicationReminders: boolean;
  resultNotifications: boolean;
  marketingMessages: boolean;
  emergencyOverrideAllowed?: boolean;
}

export interface CommunicationRequest {
  category: 'appointment' | 'medication' | 'result' | 'marketing' | 'operational' | 'emergency';
  channel: CommunicationChannel;
  language?: string;
  now?: Date;
  emergency?: boolean;
  containsSensitiveData?: boolean;
}

export interface CommunicationDecision {
  allowed: boolean;
  channel: CommunicationChannel;
  language: string;
  reason?: string;
  minimumNecessary: boolean;
}

const consentedCategories: Record<CommunicationRequest['category'], keyof CommunicationPreferences | undefined> = {
  appointment: 'appointmentReminders',
  medication: 'medicationReminders',
  result: 'resultNotifications',
  marketing: 'marketingMessages',
  operational: undefined,
  emergency: undefined,
};

function withinQuietHours(now: Date, quietHours?: CommunicationPreferences['quietHours']): boolean {
  if (!quietHours?.start || !quietHours.end) return false;
  const toMinutes = (value: string) => {
    const match = /^(\d{2}):(\d{2})$/.exec(value);
    return match ? Number(match[1]) * 60 + Number(match[2]) : undefined;
  };
  const current = now.getHours() * 60 + now.getMinutes();
  const start = toMinutes(quietHours.start);
  const end = toMinutes(quietHours.end);
  if (start === undefined || end === undefined) return false;
  return start <= end ? current >= start && current < end : current >= start || current < end;
}

export function evaluateCommunicationRequest(
  preferences: CommunicationPreferences,
  request: CommunicationRequest,
): CommunicationDecision {
  const language = request.language || preferences.preferredLanguage || 'en';
  const emergencyOverride = request.emergency === true && preferences.emergencyOverrideAllowed === true;
  const minimumNecessary = request.containsSensitiveData === true || request.category === 'emergency';

  if (!preferences.preferredChannels.includes(request.channel) && !emergencyOverride) {
    return { allowed: false, channel: request.channel, language, reason: 'Channel is not consented', minimumNecessary };
  }

  const consentKey = consentedCategories[request.category];
  if (consentKey && preferences[consentKey] !== true) {
    return { allowed: false, channel: request.channel, language, reason: 'Communication category is not consented', minimumNecessary };
  }

  if (!request.emergency && request.category !== 'emergency' && withinQuietHours(request.now ?? new Date(), preferences.quietHours)) {
    return { allowed: false, channel: request.channel, language, reason: 'Quiet hours are active', minimumNecessary };
  }

  if (request.category === 'emergency' && request.emergency !== true) {
    return { allowed: false, channel: request.channel, language, reason: 'Emergency category requires explicit emergency context', minimumNecessary };
  }

  if (request.emergency === true && !preferences.emergencyOverrideAllowed && !preferences.preferredChannels.includes(request.channel)) {
    return { allowed: false, channel: request.channel, language, reason: 'Emergency override is not authorized for this channel', minimumNecessary };
  }

  return { allowed: true, channel: request.channel, language, minimumNecessary };
}
