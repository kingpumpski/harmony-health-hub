export type PaymentRoutingMode = 'pay_before_every_step' | 'streamlined';

export type ServiceOrderPaymentStatus =
  | 'pending'
  | 'approved'
  | 'overridden'
  | 'rejected'
  | 'waived';

export type ServiceOrderFulfillmentStatus =
  | 'blocked'
  | 'released'
  | 'in_progress'
  | 'completed'
  | 'cancelled';

export interface ServiceOrderWorkflowState {
  paymentStatus: ServiceOrderPaymentStatus;
  fulfillmentStatus: ServiceOrderFulfillmentStatus;
}

export interface WorkflowTransitionResult {
  allowed: boolean;
  next?: ServiceOrderWorkflowState;
  reason?: string;
}

const RELEASEABLE_PAYMENT_STATUSES = new Set<ServiceOrderPaymentStatus>([
  'approved',
  'overridden',
  'waived',
]);

export function canReleaseServiceOrder(
  state: ServiceOrderWorkflowState,
  mode: PaymentRoutingMode,
): WorkflowTransitionResult {
  if (state.fulfillmentStatus !== 'blocked') {
    return { allowed: false, reason: 'Only blocked orders can be released.' };
  }

  if (mode === 'pay_before_every_step' && !RELEASEABLE_PAYMENT_STATUSES.has(state.paymentStatus)) {
    return { allowed: false, reason: 'Payment approval is required before release.' };
  }

  if (mode === 'streamlined' && state.paymentStatus === 'rejected') {
    return { allowed: false, reason: 'Rejected services cannot be released.' };
  }

  return {
    allowed: true,
    next: { ...state, fulfillmentStatus: 'released' },
  };
}

export function applyServiceOrderPayment(
  state: ServiceOrderWorkflowState,
  paymentStatus: Extract<ServiceOrderPaymentStatus, 'approved' | 'overridden' | 'waived' | 'rejected'>,
): ServiceOrderWorkflowState {
  const nextFulfillment = RELEASEABLE_PAYMENT_STATUSES.has(paymentStatus)
    ? 'released'
    : paymentStatus === 'rejected'
      ? 'blocked'
      : state.fulfillmentStatus;

  return {
    paymentStatus,
    fulfillmentStatus: nextFulfillment,
  };
}

export function calculateBmi(weightKg: number, heightCm: number): number | null {
  if (!Number.isFinite(weightKg) || !Number.isFinite(heightCm) || weightKg <= 0 || heightCm <= 0) {
    return null;
  }

  const heightM = heightCm / 100;
  return Number((weightKg / (heightM * heightM)).toFixed(1));
}

export function classifyBmi(bmi: number | null): string {
  if (bmi === null) return 'unknown';
  if (bmi < 18.5) return 'underweight';
  if (bmi < 25) return 'normal';
  if (bmi < 30) return 'overweight';
  return 'obesity';
}

export interface VitalPriorityInput {
  systolic?: number | null;
  diastolic?: number | null;
  pulseRate?: number | null;
  temperature?: number | null;
  oxygenSaturation?: number | null;
}

export type VitalPriority = 'critical' | 'urgent' | 'moderate' | 'routine';

export function classifyVitalPriority(vitals: VitalPriorityInput): VitalPriority {
  const { systolic, diastolic, pulseRate, temperature, oxygenSaturation } = vitals;

  if (
    (oxygenSaturation != null && oxygenSaturation < 90) ||
    (systolic != null && systolic >= 180) ||
    (diastolic != null && diastolic >= 120) ||
    (systolic != null && systolic < 80) ||
    (pulseRate != null && (pulseRate < 40 || pulseRate > 150)) ||
    (temperature != null && (temperature >= 40 || temperature < 34))
  ) {
    return 'critical';
  }

  if (
    (oxygenSaturation != null && oxygenSaturation < 94) ||
    (systolic != null && (systolic >= 160 || systolic < 90)) ||
    (diastolic != null && diastolic >= 100) ||
    (pulseRate != null && (pulseRate < 50 || pulseRate > 120)) ||
    (temperature != null && (temperature >= 38.5 || temperature < 35))
  ) {
    return 'urgent';
  }

  if (
    (systolic != null && systolic >= 140) ||
    (diastolic != null && diastolic >= 90) ||
    (pulseRate != null && (pulseRate < 60 || pulseRate > 100)) ||
    (temperature != null && temperature >= 37.5)
  ) {
    return 'moderate';
  }

  return 'routine';
}
