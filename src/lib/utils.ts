import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function generateClientId(prefix = 'MED') {
  const now = new Date();
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, '0');
  const dd = String(now.getDate()).padStart(2, '0');
  const random = Math.floor(1000 + Math.random() * 9000);
  return `${prefix}-${yyyy}${mm}${dd}-${random}`;
}

/**
 * Patient identification payloads intentionally contain only the facility's
 * business identifier. Never encode names, dates of birth, Ghana Card numbers,
 * diagnoses, insurance details, or other PHI into a wristband barcode/QR code.
 */
export function getPatientIdentityPayload(patientCode: string) {
  const normalized = patientCode.trim().replace(/[^A-Za-z0-9._-]/g, '');
  if (!normalized || normalized.length > 64) {
    throw new Error('Invalid patient identifier for machine-readable encoding.');
  }
  return `HARMONY:PATIENT:${normalized}`;
}

/**
 * Temporary compatibility renderer for the existing registration UI.
 * The payload is PHI-minimized; a future self-hosted renderer should replace
 * this third-party image service so identifiers never leave the facility.
 */
export function getQrCodeUrl(patientCode: string) {
  const payload = getPatientIdentityPayload(patientCode);
  return `https://api.qrserver.com/v1/create-qr-code/?size=240x240&margin=8&data=${encodeURIComponent(payload)}`;
}

/**
 * Code 128 is retained for wristband/label compatibility. Only the internal
 * patient identifier is encoded; no clinical or demographic information is.
 */
export function getBarcodeUrl(patientCode: string) {
  const payload = getPatientIdentityPayload(patientCode);
  return `https://barcode.tec-it.com/barcode.ashx?data=${encodeURIComponent(payload)}&code=Code128&dpi=160&quiet=1`;
}
