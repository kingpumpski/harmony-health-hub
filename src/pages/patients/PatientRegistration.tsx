import { ChangeEvent, FormEvent, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, AlertTriangle, FileCheck2, Heart, Loader2, Printer, Save, Shield, Upload, User, X } from 'lucide-react';
import { toast } from 'sonner';
import { cn, getBarcodeUrl, getQrCodeUrl } from '@/lib/utils';
import { registerPatient } from '@/lib/healthApi';
import { analyzePatientDocument, uploadPatientFile, validatePatientDocument, validateProfilePhoto } from '@/lib/patientDocuments';

interface FormData {
  patientId: string;
  ghanaCardNumber: string;
  firstName: string;
  lastName: string;
  dateOfBirth: string;
  gender: string;
  email: string;
  phone: string;
  address: string;
  city: string;
  emergencyName: string;
  emergencyRelation: string;
  emergencyPhone: string;
  insuranceProvider: string;
  policyNumber: string;
  groupNumber: string;
  insuranceExpiry: string;
  bloodType: string;
  genotype: string;
  allergies: string;
  chronicConditions: string;
  medicalHistory: string;
}

const emptyForm: FormData = {
  patientId: '', ghanaCardNumber: '', firstName: '', lastName: '', dateOfBirth: '', gender: '',
  email: '', phone: '', address: '', city: '', emergencyName: '', emergencyRelation: '',
  emergencyPhone: '', insuranceProvider: '', policyNumber: '', groupNumber: '', insuranceExpiry: '',
  bloodType: '', genotype: '', allergies: '', chronicConditions: '', medicalHistory: '',
};

const sections = [
  ['personal', 'Personal Information', User],
  ['contact', 'Contact Details', User],
  ['documents', 'Documents', Upload],
  ['emergency', 'Emergency Contact', AlertTriangle],
  ['insurance', 'Insurance', Shield],
  ['medical', 'Medical History', Heart],
] as const;

export default function PatientRegistration() {
  const navigate = useNavigate();
  const [activeSection, setActiveSection] = useState('personal');
  const [formData, setFormData] = useState<FormData>(emptyForm);
  const [hasInsurance, setHasInsurance] = useState(false);
  const [profilePhoto, setProfilePhoto] = useState<File | null>(null);
  const [documents, setDocuments] = useState<File[]>([]);
  const [analysis, setAnalysis] = useState<Record<string, string[]>>({});
  const [registered, setRegistered] = useState<{ id: string; code: string; name: string } | null>(null);
  const [saving, setSaving] = useState(false);

  const updateField = (event: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value } = event.target;
    setFormData((current) => ({ ...current, [name]: value }));
  };

  const chooseProfilePhoto = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    const validation = validateProfilePhoto(file);
    if (!validation.valid) {
      toast.error(validation.reason);
      event.target.value = '';
      return;
    }
    setProfilePhoto(file);
  };

  const chooseDocuments = (event: ChangeEvent<HTMLInputElement>) => {
    const selected = Array.from(event.target.files ?? []);
    const accepted: File[] = [];
    for (const file of selected) {
      const validation = validatePatientDocument(file);
      if (validation.valid) accepted.push(file);
      else toast.error(`${file.name}: ${validation.reason}`);
    }
    setDocuments(accepted);
    event.target.value = '';
  };

  const removeDocument = (name: string) => setDocuments((current) => current.filter((file) => file.name !== name));

  const analyzeDocument = async (file: File) => {
    try {
      const result = await analyzePatientDocument(file);
      setAnalysis((current) => ({ ...current, [file.name]: result.findings }));
      toast.success(`${file.name} checked for safe ingestion`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Document analysis failed');
    }
  };

  const resetForm = () => {
    setFormData({ ...emptyForm });
    setHasInsurance(false);
    setProfilePhoto(null);
    setDocuments([]);
    setAnalysis({});
    setRegistered(null);
    setActiveSection('personal');
  };

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault();
    if (saving) return;
    setSaving(true);

    try {
      const result = await registerPatient(formData as any);
      const patientId = result?.patient?.id;
      const patientCode = result?.patientId || '';
      if (!patientId || !patientCode) throw new Error('Registration succeeded without a patient identifier.');

      if (profilePhoto) await uploadPatientFile(patientId, profilePhoto, 'profile_photo');
      for (const document of documents) await uploadPatientFile(patientId, document, 'registration_supporting_document');

      setRegistered({ id: patientId, code: patientCode, name: `${formData.firstName} ${formData.lastName}` });
      toast.success(`Patient ${patientCode} registered successfully.`);

      try {
        const { notifyRoles } = await import('@/lib/notifications');
        await notifyRoles(['front_desk', 'nurse'], {
          title: 'New patient registered',
          message: `${formData.firstName} ${formData.lastName} (${patientCode}) is ready for triage.`,
          severity: 'info', category: 'other', link: '/vitals', relatedPatientId: patientId,
        });
      } catch (notificationError) {
        console.warn('[PatientRegistration] notification delivery failed', notificationError);
      }
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not register patient.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="animate-fade-in space-y-6">
      <div className="flex items-center gap-4">
        <button type="button" onClick={() => navigate(-1)} className="p-2 rounded-lg hover:bg-muted" aria-label="Go back">
          <ArrowLeft className="h-5 w-5" />
        </button>
        <div>
          <h1 className="text-2xl font-heading font-bold">Patient Registration</h1>
          <p className="text-muted-foreground">Create a complete patient record with governed identity and document handling.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
        <aside className="lg:col-span-1">
          <div className="card-medical p-4 sticky top-24">
            <nav className="space-y-1" aria-label="Registration sections">
              {sections.map(([id, label, Icon]) => (
                <button key={id} type="button" onClick={() => setActiveSection(id)} className={cn(
                  'w-full flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium text-left',
                  activeSection === id ? 'bg-primary text-primary-foreground' : 'hover:bg-muted text-muted-foreground',
                )}>
                  <Icon className="h-4 w-4" />{label}
                </button>
              ))}
            </nav>
          </div>
        </aside>

        <form onSubmit={handleSubmit} className="lg:col-span-3 space-y-6">
          {activeSection === 'personal' && <section className="card-medical p-6 space-y-4">
            <h2 className="text-lg font-semibold flex items-center gap-2"><User className="h-5 w-5 text-primary" />Personal Information</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Field label="First Name *" name="firstName" value={formData.firstName} onChange={updateField} required />
              <Field label="Last Name *" name="lastName" value={formData.lastName} onChange={updateField} required />
              <Field label="Date of Birth *" name="dateOfBirth" type="date" value={formData.dateOfBirth} onChange={updateField} required />
              <SelectField label="Gender *" name="gender" value={formData.gender} onChange={updateField} options={['male', 'female', 'other']} required />
              <Field label="Patient ID" name="patientId" value={formData.patientId} onChange={updateField} placeholder="Leave blank for system-generated ID" />
              <Field label="National ID / Ghana Card" name="ghanaCardNumber" value={formData.ghanaCardNumber} onChange={updateField} autoComplete="off" />
              <div className="md:col-span-2 space-y-2">
                <label className="text-sm font-medium">Profile Photo</label>
                <input type="file" accept="image/jpeg,image/png,image/webp" onChange={chooseProfilePhoto} className="input-medical" />
                {profilePhoto && <p className="text-xs text-muted-foreground">Selected: {profilePhoto.name}</p>}
              </div>
            </div>
          </section>}

          {activeSection === 'contact' && <section className="card-medical p-6 space-y-4">
            <h2 className="text-lg font-semibold">Contact Details</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Field label="Email Address" name="email" type="email" value={formData.email} onChange={updateField} autoComplete="email" />
              <Field label="Phone Number *" name="phone" type="tel" value={formData.phone} onChange={updateField} required autoComplete="tel" />
              <div className="md:col-span-2"><Field label="Address" name="address" value={formData.address} onChange={updateField} /></div>
              <Field label="City" name="city" value={formData.city} onChange={updateField} />
            </div>
          </section>}

          {activeSection === 'documents' && <section className="card-medical p-6 space-y-5">
            <div><h2 className="text-lg font-semibold flex items-center gap-2"><Upload className="h-5 w-5 text-primary" />Documents & Safe Analysis</h2><p className="text-sm text-muted-foreground mt-1">Files are validated before upload. Analysis is administrative/integrity assistance only and is never presented as a clinical diagnosis.</p></div>
            <input type="file" multiple accept="application/pdf,image/jpeg,image/png,image/webp,text/plain" onChange={chooseDocuments} className="input-medical" />
            <div className="space-y-3">
              {documents.map((file) => <div key={file.name} className="rounded-xl border p-4 space-y-3">
                <div className="flex items-center justify-between gap-3"><div className="flex items-center gap-2 min-w-0"><FileCheck2 className="h-5 w-5 shrink-0 text-primary" /><span className="truncate text-sm font-medium">{file.name}</span></div><button type="button" onClick={() => removeDocument(file.name)} aria-label={`Remove ${file.name}`}><X className="h-4 w-4" /></button></div>
                <div className="flex gap-2"><button type="button" className="btn-secondary text-sm" onClick={() => analyzeDocument(file)}>Check document</button></div>
                {analysis[file.name] && <ul className="text-xs text-muted-foreground space-y-1 list-disc pl-5">{analysis[file.name].map((item) => <li key={item}>{item}</li>)}</ul>}
              </div>)}
            </div>
          </section>}

          {activeSection === 'emergency' && <section className="card-medical p-6 space-y-4">
            <h2 className="text-lg font-semibold flex items-center gap-2"><AlertTriangle className="h-5 w-5 text-warning" />Emergency Contact</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Field label="Contact Name" name="emergencyName" value={formData.emergencyName} onChange={updateField} />
              <Field label="Relationship" name="emergencyRelation" value={formData.emergencyRelation} onChange={updateField} />
              <Field label="Phone Number" name="emergencyPhone" type="tel" value={formData.emergencyPhone} onChange={updateField} />
            </div>
          </section>}

          {activeSection === 'insurance' && <section className="card-medical p-6 space-y-4">
            <h2 className="text-lg font-semibold flex items-center gap-2"><Shield className="h-5 w-5 text-success" />Insurance</h2>
            <label className="flex items-center gap-3 text-sm font-medium"><input type="checkbox" checked={hasInsurance} onChange={(e) => setHasInsurance(e.target.checked)} />Patient has health insurance</label>
            {hasInsurance && <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Field label="Insurance Provider *" name="insuranceProvider" value={formData.insuranceProvider} onChange={updateField} required />
              <Field label="Policy Number *" name="policyNumber" value={formData.policyNumber} onChange={updateField} required />
              <Field label="Group Number" name="groupNumber" value={formData.groupNumber} onChange={updateField} />
              <Field label="Expiry Date *" name="insuranceExpiry" type="date" value={formData.insuranceExpiry} onChange={updateField} required />
            </div>}
          </section>}

          {activeSection === 'medical' && <section className="card-medical p-6 space-y-4">
            <h2 className="text-lg font-semibold flex items-center gap-2"><Heart className="h-5 w-5 text-critical" />Medical History</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <SelectField label="Blood Type" name="bloodType" value={formData.bloodType} onChange={updateField} options={['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']} />
              <Field label="Genotype" name="genotype" value={formData.genotype} onChange={updateField} placeholder="e.g. AA, AS, SS" />
              <TextAreaField label="Chronic Conditions" name="chronicConditions" value={formData.chronicConditions} onChange={updateField} />
              <TextAreaField label="Known Allergies" name="allergies" value={formData.allergies} onChange={updateField} />
              <div className="md:col-span-2"><TextAreaField label="Previous Medical Conditions / History" name="medicalHistory" value={formData.medicalHistory} onChange={updateField} /></div>
            </div>
          </section>}

          {registered && <section className="card-medical p-6 border-primary/20 bg-primary/5 print:break-inside-avoid" id="patient-id-card">
            <div className="flex items-start justify-between gap-4"><div><p className="text-xs uppercase tracking-[0.2em] text-primary">Registration complete</p><h2 className="text-xl font-semibold">{registered.name}</h2><p className="text-sm text-muted-foreground">Patient ID: {registered.code}</p></div><button type="button" className="btn-secondary print:hidden" onClick={() => window.print()}><Printer className="h-4 w-4" />Print ID</button></div>
            <div className="mt-5 grid grid-cols-1 md:grid-cols-[180px_1fr] gap-5 items-center">
              <div className="rounded-2xl bg-white p-3 border"><img src={getQrCodeUrl(registered.code)} alt="Machine-readable patient QR code" className="w-full aspect-square" /></div>
              <div className="space-y-3"><p className="text-sm font-medium">Machine-readable patient identity</p><img src={getBarcodeUrl(registered.code)} alt="Machine-readable patient barcode" className="h-20 w-full object-contain bg-white border rounded-xl" /><p className="text-xs text-muted-foreground">The QR/barcode contains only the facility patient identifier. Clinical and demographic information is not encoded.</p></div>
            </div>
          </section>}

          <div className="flex flex-wrap items-center justify-end gap-3 print:hidden">
            {registered && <button type="button" className="btn-secondary" onClick={resetForm}>Register Another Patient</button>}
            <button type="button" className="btn-secondary" onClick={() => navigate(-1)}>Cancel</button>
            {!registered && <button type="submit" className="btn-primary" disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}{saving ? 'Registering…' : 'Register Patient'}</button>}
          </div>
        </form>
      </div>
    </div>
  );
}

function Field({ label, name, value, onChange, type = 'text', required = false, placeholder, autoComplete }: { label: string; name: keyof FormData; value: string; onChange: (event: ChangeEvent<HTMLInputElement>) => void; type?: string; required?: boolean; placeholder?: string; autoComplete?: string }) {
  return <div><label htmlFor={name} className="block text-sm font-medium mb-2">{label}</label><input id={name} type={type} name={name} value={value} onChange={onChange} required={required} placeholder={placeholder} autoComplete={autoComplete} className="input-medical" /></div>;
}

function TextAreaField({ label, name, value, onChange }: { label: string; name: keyof FormData; value: string; onChange: (event: ChangeEvent<HTMLTextAreaElement>) => void }) {
  return <div className="space-y-2"><label htmlFor={name} className="block text-sm font-medium">{label}</label><textarea id={name} name={name} value={value} onChange={onChange} className="input-medical min-h-24" /></div>;
}

function SelectField({ label, name, value, onChange, options, required = false }: { label: string; name: keyof FormData; value: string; onChange: (event: ChangeEvent<HTMLSelectElement>) => void; options: string[]; required?: boolean }) {
  return <div><label htmlFor={name} className="block text-sm font-medium mb-2">{label}</label><select id={name} name={name} value={value} onChange={onChange} required={required} className="input-medical"><option value="">Select</option>{options.map((option) => <option key={option} value={option}>{option}</option>)}</select></div>;
}
