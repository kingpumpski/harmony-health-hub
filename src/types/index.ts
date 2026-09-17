export type UserRole = 
  | 'admin'
  | 'practitioner'
  | 'nurse'
  | 'midwife'
  | 'specialist_nurse'
  | 'lab_technician'
  | 'pharmacist'
  | 'accountant'
  | 'front_desk'
  | 'canteen'
  | 'patient';

export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: UserRole;
  avatar?: string;
  department?: string;
  specialization?: string;
}

export interface Patient {
  id: string;
  patientId: string;
  ghanaCardNumber?: string;
  fullName?: string;
  firstName: string;
  lastName: string;
  dateOfBirth: string;
  gender: 'male' | 'female' | 'other';
  address: string;
  email: string;
  phone: string;
  nextOfKin?: {
    name: string;
    relationship: string;
    phone: string;
  };
  profilePhoto?: string;
  insuranceProvider?: string;
  insuranceNumber?: string;
  emergencyContact: {
    name: string;
    relationship: string;
    phone: string;
  };
  insurance?: {
    provider: string;
    policyNumber: string;
    groupNumber?: string;
    expiryDate: string;
    coverageType: string;
  };
  bloodType?: string;
  genotype?: string;
  allergies?: string[];
  chronicConditions?: string[];
  medicalHistory?: string[];
  registrationDate: string;
  status: 'active' | 'inactive' | 'discharged';
}

export interface Appointment {
  id: string;
  patientId: string;
  patientName: string;
  practitionerId: string;
  practitionerName: string;
  date: string;
  time: string;
  type: 'consultation' | 'follow-up' | 'procedure' | 'lab' | 'fertility';
  status: 'scheduled' | 'checked-in' | 'in-progress' | 'completed' | 'cancelled';
  notes?: string;
  department: string;
}

export interface VitalSigns {
  id: string;
  patientId: string;
  recordedBy: string;
  recordedAt: string;
  bloodPressure: {
    systolic: number;
    diastolic: number;
  };
  heartRate: number;
  temperature: number;
  respiratoryRate: number;
  oxygenSaturation: number;
  weight?: number;
  height?: number;
  notes?: string;
  isCritical: boolean;
}

export interface Encounter {
  id: string;
  patientId: string;
  practitionerId: string;
  appointmentId?: string;
  date: string;
  chiefComplaint: string;
  symptoms: string[];
  diagnosis: string;
  treatmentPlan: string;
  prescriptions?: Prescription[];
  labRequests?: LabRequest[];
  procedureRequests?: ProcedureRequest[];
  notes: string;
  status: 'draft' | 'completed' | 'approved';
}

export interface Prescription {
  id: string;
  encounterId: string;
  patientId: string;
  drugName: string;
  dosage: string;
  frequency: string;
  duration: string;
  quantity: number;
  instructions: string;
  status: 'pending' | 'dispensed' | 'partially-dispensed';
}

export interface LabRequest {
  id: string;
  encounterId: string;
  patientId: string;
  testName: string;
  testType: string;
  priority: 'routine' | 'urgent' | 'stat';
  status: 'pending' | 'in-progress' | 'completed' | 'approved';
  requestedBy: string;
  requestedAt: string;
  results?: LabResult;
}

export interface LabResult {
  id: string;
  labRequestId: string;
  results: {
    parameter: string;
    value: string;
    unit: string;
    referenceRange: string;
    isAbnormal: boolean;
  }[];
  performedBy: string;
  performedAt: string;
  approvedBy?: string;
  approvedAt?: string;
  notes?: string;
}

export interface ProcedureRequest {
  id: string;
  encounterId: string;
  patientId: string;
  procedureName: string;
  indication: string;
  priority: 'routine' | 'urgent' | 'emergency';
  scheduledDate?: string;
  status: 'requested' | 'scheduled' | 'in-progress' | 'completed';
}

export interface Admission {
  id: string;
  patientId: string;
  admissionDate: string;
  dischargeDate?: string;
  ward: string;
  bed: string;
  admittingDoctor: string;
  diagnosis: string;
  status: 'admitted' | 'discharged' | 'transferred';
  nursingNotes: NursingNote[];
  medications: InpatientMedication[];
}

export interface NursingNote {
  id: string;
  admissionId: string;
  nurseId: string;
  nurseName: string;
  note: string;
  createdAt: string;
}

export interface InpatientMedication {
  id: string;
  admissionId: string;
  drugName: string;
  dosage: string;
  frequency: string;
  route: string;
  administrationTimes: {
    scheduledTime: string;
    administeredAt?: string;
    administeredBy?: string;
    status: 'pending' | 'administered' | 'missed' | 'held';
  }[];
}

export interface Ward {
  id: string;
  name: string;
  type: 'general' | 'icu' | 'maternity' | 'pediatric' | 'surgical' | 'private';
  beds: Bed[];
  capacity: number;
  occupancy: number;
}

export interface Bed {
  id: string;
  wardId: string;
  bedNumber: string;
  status: 'available' | 'occupied' | 'maintenance' | 'reserved';
  currentPatientId?: string;
  dailyRate: number;
}

export interface Invoice {
  id: string;
  patientId: string;
  patientName: string;
  invoiceNumber: string;
  date: string;
  dueDate: string;
  items: InvoiceItem[];
  subtotal: number;
  tax: number;
  discount: number;
  total: number;
  insuranceCovered?: number;
  patientResponsibility: number;
  status: 'draft' | 'pending' | 'paid' | 'partial' | 'overdue';
  paymentHistory: Payment[];
}

export interface InvoiceItem {
  id: string;
  description: string;
  category: 'consultation' | 'procedure' | 'lab' | 'medication' | 'accommodation' | 'other';
  quantity: number;
  unitPrice: number;
  total: number;
}

export interface Payment {
  id: string;
  invoiceId: string;
  amount: number;
  method: 'cash' | 'card' | 'insurance' | 'bank-transfer';
  date: string;
  reference?: string;
  receivedBy: string;
}

export interface Drug {
  id: string;
  name: string;
  genericName: string;
  category: string;
  unitOfMeasure: string;
  stockLevel: number;
  reorderLevel: number;
  unitPrice: number;
  expiryDate: string;
  batchNumber: string;
  supplier: string;
}

export interface FertilityTreatment {
  id: string;
  patientId: string;
  partnerId?: string;
  treatmentType: 'IVF' | 'IUI' | 'ICSI' | 'egg-freezing' | 'consultation';
  cycleNumber: number;
  startDate: string;
  status: 'planning' | 'stimulation' | 'retrieval' | 'transfer' | 'monitoring' | 'completed';
  medications: string[];
  procedures: string[];
  notes: string;
  outcome?: 'positive' | 'negative' | 'ongoing';
}

export interface Notification {
  id: string;
  type: 'lab-result' | 'critical-vital' | 'appointment' | 'medication' | 'system';
  title: string;
  message: string;
  priority: 'low' | 'medium' | 'high' | 'critical';
  recipientId: string;
  relatedEntityId?: string;
  relatedEntityType?: string;
  isRead: boolean;
  createdAt: string;
}

export interface SoundAlertConfig {
  id: string;
  name: string;
  category: 'critical' | 'notification' | 'reminder' | 'emergency';
  enabled: boolean;
  soundFile?: string;
}

export interface PublicHealthReportTemplate {
  id: string;
  name: string;
  frequency: 'Daily' | 'Weekly' | 'Monthly' | 'Quarterly';
  lastGenerated?: string;
}

export interface RosterShift {
  day: string;
  shift: 'Morning' | 'Afternoon' | 'Night';
  assignedTeam: string;
}

export interface AISpecialistAnalysis {
  specialist: string;
  score: number;
  recommendation: string;
  riskLevel: 'low' | 'moderate' | 'high' | 'critical';
}
