import { supabase } from '@/integrations/supabase/client';

const MAX_DOCUMENT_SIZE = 10 * 1024 * 1024;
const MAX_PROFILE_PHOTO_SIZE = 5 * 1024 * 1024;

const DOCUMENT_TYPES = new Set([
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/webp',
  'text/plain',
]);

const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

export interface DocumentValidationResult {
  valid: boolean;
  reason?: string;
}

export interface DocumentAnalysisResult {
  findings: string[];
  sha256: string;
  fileName: string;
  mimeType: string;
  size: number;
  isClinicalConclusion: false;
}

function sanitizeFileName(fileName: string) {
  return fileName.replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120) || 'document';
}

export function validatePatientDocument(file: File): DocumentValidationResult {
  if (!file.size) return { valid: false, reason: 'The selected file is empty.' };
  if (file.size > MAX_DOCUMENT_SIZE) {
    return { valid: false, reason: 'Supporting documents must be 10 MB or smaller.' };
  }
  if (!DOCUMENT_TYPES.has(file.type)) {
    return { valid: false, reason: 'Supported documents are PDF, JPEG, PNG, WebP, or plain text.' };
  }
  return { valid: true };
}

export function validateProfilePhoto(file: File): DocumentValidationResult {
  if (!file.size) return { valid: false, reason: 'The selected photo is empty.' };
  if (file.size > MAX_PROFILE_PHOTO_SIZE) {
    return { valid: false, reason: 'Profile photos must be 5 MB or smaller.' };
  }
  if (!IMAGE_TYPES.has(file.type)) {
    return { valid: false, reason: 'Profile photos must be JPEG, PNG, or WebP images.' };
  }
  return { valid: true };
}

async function sha256(file: File) {
  const buffer = await file.arrayBuffer();
  const digest = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Performs only safe, deterministic document triage in the browser.
 * It does not make diagnostic, medication, interaction, or treatment claims.
 * A future OCR/AI adapter can consume this contract while keeping its output
 * explicitly labelled as extracted text/administrative suggestions.
 */
export async function analyzePatientDocument(file: File): Promise<DocumentAnalysisResult> {
  const validation = validatePatientDocument(file);
  if (!validation.valid) throw new Error(validation.reason);

  const hash = await sha256(file);
  const findings = [
    `Document received: ${file.name}`,
    `File type: ${file.type || 'unknown'}`,
    `Integrity fingerprint: SHA-256 ${hash.slice(0, 16)}…`,
    'No clinical conclusion was generated. Review the source document before using any information in patient care.',
  ];

  return {
    findings,
    sha256: hash,
    fileName: file.name,
    mimeType: file.type,
    size: file.size,
    isClinicalConclusion: false,
  };
}

export async function uploadPatientFile(patientId: string, file: File, documentType: string) {
  const validation = documentType === 'profile_photo'
    ? validateProfilePhoto(file)
    : validatePatientDocument(file);
  if (!validation.valid) throw new Error(validation.reason);

  const { data: authData, error: authError } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!authData.user) throw new Error('You must be signed in to upload a patient document.');

  const safeName = sanitizeFileName(file.name);
  const path = `${patientId}/${crypto.randomUUID()}-${safeName}`;
  const { error: uploadError } = await supabase.storage
    .from('patient-documents')
    .upload(path, file, { contentType: file.type, upsert: false });
  if (uploadError) throw uploadError;

  const { error: metadataError } = await supabase.rpc('upload_patient_document_metadata', {
    _patient_id: patientId,
    _document_type: documentType,
    _file_name: file.name,
    _storage_path: path,
    _mime_type: file.type,
    _file_size: file.size,
    _notes: 'Uploaded during patient registration.',
  });

  if (metadataError) {
    await supabase.storage.from('patient-documents').remove([path]);
    throw metadataError;
  }

  return { path, fileName: file.name };
}
