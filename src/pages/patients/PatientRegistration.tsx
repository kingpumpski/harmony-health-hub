import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Save, User, Phone, Shield, Heart, AlertTriangle, Upload, QrCode, Barcode, ClipboardCheck, Sparkles, Loader2, ScanLine, CheckCircle, AlertCircle } from 'lucide-react';
import { cn, generateClientId, getBarcodeUrl, getQrCodeUrl } from '@/lib/utils';
import { analyzeDocument, registerPatient } from '@/lib/healthApi';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

interface FormSection {
  id: string;
  title: string;
  icon: React.ElementType;
}

const formSections: FormSection[] = [
  { id: 'personal', title: 'Personal Information', icon: User },
  { id: 'contact', title: 'Contact Details', icon: Phone },
  { id: 'documents', title: 'Documents', icon: Upload },
  { id: 'emergency', title: 'Emergency Contact', icon: AlertTriangle },
  { id: 'insurance', title: 'Insurance', icon: Shield },
  { id: 'medical', title: 'Medical History', icon: Heart },
];

export default function PatientRegistration() {
  const navigate = useNavigate();
  const [activeSection, setActiveSection] = useState('personal');
  const [hasInsurance, setHasInsurance] = useState(false);
  const [profilePhotoName, setProfilePhotoName] = useState('');
  const [uploadedDocuments, setUploadedDocuments] = useState<File[]>([]);
  const [documentUploadNames, setDocumentUploadNames] = useState('');
  const [documentAnalysis, setDocumentAnalysis] = useState<string[]>([]);
  const [registeredPatientId, setRegisteredPatientId] = useState('');
  const [idScanFile, setIdScanFile] = useState<File | null>(null);
  const [isScanning, setIsScanning] = useState(false);
  const [scanResult, setScanResult] = useState<{ success: boolean; message: string; confidence?: number } | null>(null);
  const initialFormState = {
    patientId: '',
    ghanaCardNumber: '',
    firstName: '',
    lastName: '',
    dateOfBirth: '',
    gender: '',
    email: '',
    phone: '',
    address: '',
    city: '',
    emergencyName: '',
    emergencyRelation: '',
    emergencyPhone: '',
    insuranceProvider: '',
    policyNumber: '',
    groupNumber: '',
    insuranceExpiry: '',
    bloodType: '',
    genotype: '',
    allergies: '',
    chronicConditions: '',
    medicalHistory: '',
  };
  const [formData, setFormData] = useState(initialFormState);
  const [registeredPatientData, setRegisteredPatientData] = useState<typeof initialFormState | null>(null);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (files.length) {
      setUploadedDocuments(files);
      setProfilePhotoName(files.map((file) => file.name).join(', '));
    }
  };

  const handleDocumentUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (files.length) {
      setUploadedDocuments(files);
      setDocumentUploadNames(files.map((file) => file.name).join(', '));
    }
  };

  const handleAnalyzeDocuments = async () => {
    if (!uploadedDocuments.length) return;
    const analysis = await analyzeDocument(uploadedDocuments[0]);
    if (analysis.findings) {
      setDocumentAnalysis(analysis.findings);
    }
  };

  const handleIdScanUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      setIdScanFile(file);
      setScanResult(null);
    }
  };

  const handleScanId = async () => {
    if (!idScanFile) return;
    
    setIsScanning(true);
    setScanResult(null);
    
    try {
      const formData = new FormData();
      formData.append('file', idScanFile);
      
      const { data, error } = await supabase.functions.invoke('scan-id-document', {
        body: formData,
      });
      
      if (error) throw error;
      
      if (data?.success && data?.data) {
        const extracted = data.data;
        
        // Auto-fill the form with extracted data
        setFormData(prev => ({
          ...prev,
          firstName: extracted.firstName || prev.firstName,
          lastName: extracted.lastName || prev.lastName,
          dateOfBirth: extracted.dateOfBirth || prev.dateOfBirth,
          gender: extracted.gender || prev.gender,
          ghanaCardNumber: extracted.ghanaCardNumber || prev.ghanaCardNumber,
          address: extracted.address || prev.address,
          city: extracted.city || prev.city,
          phone: extracted.phone || prev.phone,
          email: extracted.email || prev.email,
        }));
        
        setScanResult({
          success: true,
          message: data.message || 'ID scanned successfully',
          confidence: extracted.confidence
        });
        
        toast({
          title: 'ID Scanned Successfully',
          description: `Extracted ${extracted.documentType || 'ID'} information with ${extracted.confidence || 0}% confidence. Please verify the auto-filled data.`,
        });
        
        // Move to personal section to show filled data
        setActiveSection('personal');
      } else if (data?.error) {
        throw new Error(data.error);
      }
    } catch (err: any) {
      console.error('ID scan error:', err);
      setScanResult({
        success: false,
        message: err.message || 'Failed to scan ID document'
      });
      toast({
        title: 'Scan Failed',
        description: err.message || 'Could not extract information from the ID document',
        variant: 'destructive'
      });
    } finally {
      setIsScanning(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const payload = { ...formData };

    if (uploadedDocuments.length) {
      await handleAnalyzeDocuments();
    }

    try {
      const result: any = await registerPatient(payload as any);
      const newCode = result?.patientId || '';
      setFormData((current) => ({ ...current, patientId: newCode }));
      setRegisteredPatientId(newCode);
      setRegisteredPatientData({ ...payload, patientId: newCode });

      // Notify front desk + nurses that a new patient is ready for triage
      const { notifyRoles } = await import('@/lib/notifications');
      await notifyRoles(['front_desk', 'nurse'], {
        title: 'New patient registered',
        message: `${payload.firstName} ${payload.lastName} (${newCode}) is ready for triage.`,
        severity: 'info',
        category: 'other',
        link: '/vitals',
        relatedPatientId: result?.patient?.id,
      });

      const audio = new Audio('data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2teleQ4fk9/qvYIwA2Orzdy/dCANgtnv28RMCx/I+fjObiYNvPT34oM7ChLe//jljT4JGf//+NiVRg4a//7/wZ1ODSQG///cpVgXMhD/9t6lYhg7DP7v2ZhnFjER/+fbnW0ZOg7//dWiaR8yDP/z1KBtJTkN+fjWoW8pMg793tSdcSUoEPz436J2IykQ//baoHUlKBD///emeicuE/7326F3IyYS/fnbpnwnKBL///2me');
      audio.volume = 0.3;
      audio.play().catch(() => {});
    } catch (err: any) {
      const { toast } = await import('@/hooks/use-toast');
      toast({ title: 'Registration failed', description: err.message ?? 'Could not save patient', variant: 'destructive' });
    }
  };


  return (
    <div className="animate-fade-in">
      {/* Header */}
      <div className="flex items-center gap-4 mb-6">
        <button
          onClick={() => navigate(-1)}
          className="p-2 rounded-lg hover:bg-muted transition-colors"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div>
          <h1 className="text-2xl font-heading font-bold">Patient Registration</h1>
          <p className="text-muted-foreground">Register a new patient in the system</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
        {/* Section Navigation */}
        <div className="lg:col-span-1">
          <div className="card-medical p-4 sticky top-24">
            <nav className="space-y-1">
              {formSections.map((section) => (
                <button
                  key={section.id}
                  onClick={() => setActiveSection(section.id)}
                  className={cn(
                    'w-full flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-all',
                    activeSection === section.id
                      ? 'bg-primary text-primary-foreground'
                      : 'hover:bg-muted text-muted-foreground hover:text-foreground'
                  )}
                >
                  <section.icon className="w-4 h-4" />
                  {section.title}
                </button>
              ))}
            </nav>
          </div>
        </div>

        {/* Form */}
        <div className="lg:col-span-3">
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Personal Information */}
            <div className={cn('card-medical p-6', activeSection !== 'personal' && 'lg:hidden')}>
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <User className="w-5 h-5 text-primary" />
                Personal Information
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium mb-2">First Name *</label>
                  <input
                    type="text"
                    name="firstName"
                    value={formData.firstName}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Last Name *</label>
                  <input
                    type="text"
                    name="lastName"
                    value={formData.lastName}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Date of Birth *</label>
                  <input
                    type="date"
                    name="dateOfBirth"
                    value={formData.dateOfBirth}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Gender *</label>
                  <select
                    name="gender"
                    value={formData.gender}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  >
                    <option value="">Select gender</option>
                    <option value="male">Male</option>
                    <option value="female">Female</option>
                    <option value="other">Other</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Patient ID</label>
                  <input
                    type="text"
                    name="patientId"
                    value={formData.patientId}
                    onChange={handleInputChange}
                    className="input-medical"
                    placeholder="Auto-generated or staff-provided"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Ghana Card Number</label>
                  <input
                    type="text"
                    name="ghanaCardNumber"
                    value={formData.ghanaCardNumber}
                    onChange={handleInputChange}
                    className="input-medical"
                    placeholder="Enter National ID number"
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium mb-2">Profile Photo</label>
                  <input type="file" accept="image/*" onChange={handleFileUpload} className="input-medical" />
                  {profilePhotoName && <p className="text-sm text-muted-foreground mt-2">Selected photo: {profilePhotoName}</p>}
                </div>
              </div>
            </div>

            {/* AI ID Scanner - Documents Section */}
            <div className={cn('card-medical p-6', activeSection !== 'documents' && 'lg:hidden')}>
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <ScanLine className="w-5 h-5 text-primary" />
                AI-Powered ID Scanner
              </h2>
              
              <div className="space-y-4">
                {/* AI Scanner Info Banner */}
                <div className="rounded-xl bg-gradient-to-r from-primary/10 to-accent/10 border border-primary/20 p-4">
                  <div className="flex items-start gap-3">
                    <div className="w-10 h-10 rounded-lg bg-primary/20 flex items-center justify-center flex-shrink-0">
                      <Sparkles className="w-5 h-5 text-primary" />
                    </div>
                    <div>
                      <h3 className="font-medium text-sm">Smart ID Recognition</h3>
                      <p className="text-sm text-muted-foreground mt-1">
                        Upload a photo of the patient&apos;s ID card (Ghana Card, Passport, or Driver&apos;s License) and our AI will automatically extract and fill in their biodata information.
                      </p>
                    </div>
                  </div>
                </div>

                {/* Upload Area */}
                <div className="border-2 border-dashed border-border rounded-xl p-6 text-center hover:border-primary/50 transition-colors">
                  <input
                    type="file"
                    accept="image/*"
                    onChange={handleIdScanUpload}
                    className="hidden"
                    id="id-scan-upload"
                  />
                  <label htmlFor="id-scan-upload" className="cursor-pointer">
                    <div className="flex flex-col items-center gap-3">
                      <div className="w-16 h-16 rounded-2xl bg-muted flex items-center justify-center">
                        <Upload className="w-8 h-8 text-muted-foreground" />
                      </div>
                      <div>
                        <p className="font-medium">Upload ID Document</p>
                        <p className="text-sm text-muted-foreground">
                          Drag and drop or click to select
                        </p>
                      </div>
                    </div>
                  </label>
                </div>

                {/* Selected File & Scan Button */}
                {idScanFile && (
                  <div className="rounded-xl border border-border p-4">
                    <div className="flex items-center justify-between gap-4">
                      <div className="flex items-center gap-3">
                        <div className="w-12 h-12 rounded-lg bg-muted flex items-center justify-center overflow-hidden">
                          <img 
                            src={URL.createObjectURL(idScanFile)} 
                            alt="ID preview" 
                            className="w-full h-full object-cover"
                          />
                        </div>
                        <div>
                          <p className="font-medium text-sm">{idScanFile.name}</p>
                          <p className="text-xs text-muted-foreground">
                            {(idScanFile.size / 1024).toFixed(1)} KB
                          </p>
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={handleScanId}
                        disabled={isScanning}
                        className="btn-primary"
                      >
                        {isScanning ? (
                          <>
                            <Loader2 className="w-4 h-4 animate-spin" />
                            Scanning...
                          </>
                        ) : (
                          <>
                            <Sparkles className="w-4 h-4" />
                            Scan with AI
                          </>
                        )}
                      </button>
                    </div>
                  </div>
                )}

                {/* Scan Result */}
                {scanResult && (
                  <div className={cn(
                    'rounded-xl border p-4',
                    scanResult.success 
                      ? 'border-success/30 bg-success/5' 
                      : 'border-critical/30 bg-critical/5'
                  )}>
                    <div className="flex items-start gap-3">
                      {scanResult.success ? (
                        <CheckCircle className="w-5 h-5 text-success flex-shrink-0" />
                      ) : (
                        <AlertCircle className="w-5 h-5 text-critical flex-shrink-0" />
                      )}
                      <div>
                        <p className={cn(
                          'font-medium text-sm',
                          scanResult.success ? 'text-success' : 'text-critical'
                        )}>
                          {scanResult.success ? 'Extraction Successful' : 'Extraction Failed'}
                        </p>
                        <p className="text-sm text-muted-foreground mt-1">
                          {scanResult.message}
                        </p>
                        {scanResult.confidence && (
                          <div className="mt-2">
                            <div className="flex items-center gap-2">
                              <div className="flex-1 h-2 bg-muted rounded-full overflow-hidden">
                                <div 
                                  className={cn(
                                    'h-full rounded-full transition-all',
                                    scanResult.confidence >= 80 ? 'bg-success' : 
                                    scanResult.confidence >= 60 ? 'bg-warning' : 'bg-critical'
                                  )}
                                  style={{ width: `${scanResult.confidence}%` }}
                                />
                              </div>
                              <span className="text-xs font-medium">{scanResult.confidence}%</span>
                            </div>
                            <p className="text-xs text-muted-foreground mt-1">
                              {scanResult.confidence >= 80 
                                ? 'High confidence - data is likely accurate' 
                                : 'Lower confidence - please verify the extracted data'}
                            </p>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                )}

                {/* Manual Document Upload */}
                <div className="pt-4 border-t border-border">
                  <label className="block text-sm font-medium mb-2">Additional Supporting Documents</label>
                  <input
                    type="file"
                    multiple
                    accept="image/*,.pdf"
                    onChange={handleDocumentUpload}
                    className="input-medical"
                  />
                  {documentUploadNames && (
                    <p className="text-sm text-muted-foreground mt-2">
                      Uploaded: {documentUploadNames}
                    </p>
                  )}
                </div>
              </div>
            </div>

            {/* Contact Details */}
            <div className={cn('card-medical p-6', activeSection !== 'contact' && 'lg:hidden')}>
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <Phone className="w-5 h-5 text-primary" />
                Contact Details
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium mb-2">Email Address *</label>
                  <input
                    type="email"
                    name="email"
                    value={formData.email}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Phone Number *</label>
                  <input
                    type="tel"
                    name="phone"
                    value={formData.phone}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium mb-2">Address</label>
                  <input
                    type="text"
                    name="address"
                    value={formData.address}
                    onChange={handleInputChange}
                    className="input-medical"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">City</label>
                  <input
                    type="text"
                    name="city"
                    value={formData.city}
                    onChange={handleInputChange}
                    className="input-medical"
                  />
                </div>
              </div>
            </div>

            {/* Emergency Contact */}
            <div className={cn('card-medical p-6', activeSection !== 'emergency' && 'lg:hidden')}>
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <AlertTriangle className="w-5 h-5 text-warning" />
                Emergency Contact
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium mb-2">Contact Name *</label>
                  <input
                    type="text"
                    name="emergencyName"
                    value={formData.emergencyName}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Relationship *</label>
                  <input
                    type="text"
                    name="emergencyRelation"
                    value={formData.emergencyRelation}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Phone Number *</label>
                  <input
                    type="tel"
                    name="emergencyPhone"
                    value={formData.emergencyPhone}
                    onChange={handleInputChange}
                    className="input-medical"
                    required
                  />
                </div>
              </div>
            </div>

            {/* Insurance */}
            <div className={cn('card-medical p-6', activeSection !== 'insurance' && 'lg:hidden')}>
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <Shield className="w-5 h-5 text-success" />
                Insurance Information
              </h2>
              <div className="mb-4">
                <label className="flex items-center gap-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={hasInsurance}
                    onChange={(e) => setHasInsurance(e.target.checked)}
                    className="w-5 h-5 rounded border-input text-primary focus:ring-primary"
                  />
                  <span className="font-medium">Patient has health insurance</span>
                </label>
              </div>
              {hasInsurance && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 animate-slide-in">
                  <div>
                    <label className="block text-sm font-medium mb-2">Insurance Provider *</label>
                    <input
                      type="text"
                      name="insuranceProvider"
                      value={formData.insuranceProvider}
                      onChange={handleInputChange}
                      className="input-medical"
                      required={hasInsurance}
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-2">Policy Number *</label>
                    <input
                      type="text"
                      name="policyNumber"
                      value={formData.policyNumber}
                      onChange={handleInputChange}
                      className="input-medical"
                      required={hasInsurance}
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-2">Group Number</label>
                    <input
                      type="text"
                      name="groupNumber"
                      value={formData.groupNumber}
                      onChange={handleInputChange}
                      className="input-medical"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-2">Expiry Date *</label>
                    <input
                      type="date"
                      name="insuranceExpiry"
                      value={formData.insuranceExpiry}
                      onChange={handleInputChange}
                      className="input-medical"
                      required={hasInsurance}
                    />
                  </div>
                </div>
              )}
            </div>

            {/* Medical History */}
            <div className={cn('card-medical p-6', activeSection !== 'medical' && 'lg:hidden')}>
              <h2 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <Heart className="w-5 h-5 text-critical" />
                Medical History
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium mb-2">Blood Type</label>
                  <select
                    name="bloodType"
                    value={formData.bloodType}
                    onChange={handleInputChange}
                    className="input-medical"
                  >
                    <option value="">Select blood type</option>
                    <option value="A+">A+</option>
                    <option value="A-">A-</option>
                    <option value="B+">B+</option>
                    <option value="B-">B-</option>
                    <option value="AB+">AB+</option>
                    <option value="AB-">AB-</option>
                    <option value="O+">O+</option>
                    <option value="O-">O-</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium mb-2">Genotype</label>
                  <input
                    type="text"
                    name="genotype"
                    value={formData.genotype}
                    onChange={handleInputChange}
                    className="input-medical"
                    placeholder="e.g. AS, AA, SS"
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium mb-2">Chronic Conditions</label>
                  <textarea
                    name="chronicConditions"
                    value={formData.chronicConditions}
                    onChange={handleInputChange}
                    className="input-medical min-h-20"
                    placeholder="Diabetes, hypertension, asthma, etc."
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium mb-2">Known Allergies</label>
                  <textarea
                    name="allergies"
                    value={formData.allergies}
                    onChange={handleInputChange}
                    className="input-medical min-h-20"
                    placeholder="List any known allergies (medications, food, etc.)"
                  />
                </div>
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium mb-2">Previous Medical Conditions</label>
                  <textarea
                    name="medicalHistory"
                    value={formData.medicalHistory}
                    onChange={handleInputChange}
                    className="input-medical min-h-24"
                    placeholder="List any previous surgeries, chronic conditions, or significant medical history"
                  />
                </div>
              </div>
            </div>

            {registeredPatientId && registeredPatientData && (
              <div className="card-medical p-6 border-primary/20 bg-primary/5">
                <div className="flex flex-col gap-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm uppercase tracking-[0.2em] text-primary">Registration Complete</p>
                      <h2 className="text-xl font-semibold">Client ID: {registeredPatientId}</h2>
                    </div>
                    <div className="text-right text-sm text-muted-foreground">
                      <p>{registeredPatientData.firstName} {registeredPatientData.lastName}</p>
                      <p>{registeredPatientData.phone}</p>
                    </div>
                  </div>

                  <div className="grid gap-4 lg:grid-cols-[1fr_180px]">
                    <div className="space-y-2">
                      <p className="text-sm font-medium">Wristband / ID Preview</p>
                      <div className="rounded-3xl border border-border bg-card p-4">
                        <div className="space-y-3">
                          <p className="font-medium">{registeredPatientData.firstName} {registeredPatientData.lastName}</p>
                          <p className="text-xs uppercase tracking-[0.2em] text-muted-foreground">{registeredPatientData.ghanaCardNumber || 'No Ghana Card'}</p>
                          <p className="text-sm text-muted-foreground">DOB: {registeredPatientData.dateOfBirth}</p>
                          <div className="mt-3 flex flex-col gap-3 items-start">
                            <img src={getQrCodeUrl(registeredPatientId)} alt="Patient QR code" className="h-36 w-36 rounded-2xl border border-border bg-white" />
                            <img src={getBarcodeUrl(registeredPatientId)} alt="Patient barcode" className="h-16 w-full rounded-2xl border border-border bg-white object-contain" />
                          </div>
                        </div>
                      </div>
                    </div>
                    <div className="rounded-3xl border border-border bg-card p-4">
                      <p className="text-sm font-medium mb-2">Uploaded Documents</p>
                      <p className="text-sm text-muted-foreground">{profilePhotoName ? `Photo: ${profilePhotoName}` : 'No profile image uploaded.'}</p>
                      <p className="text-sm text-muted-foreground">{documentUploadNames ? `Documents: ${documentUploadNames}` : 'No supporting documents uploaded.'}</p>
                      <p className="mt-4 text-sm font-medium">Next steps</p>
                      <ul className="list-disc list-inside text-sm text-muted-foreground space-y-1">
                        <li>Save the patient record to the clinical registry.</li>
                        <li>Print the wristband or attach the QR code to the chart.</li>
                        <li>Review document analysis for referral notes.</li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Actions */}
            <div className="flex items-center justify-end gap-4">
              <button type="button" onClick={() => navigate(-1)} className="btn-secondary">
                Cancel
              </button>
              <button type="submit" className="btn-primary">
                <Save className="w-4 h-4" />
                Register Patient
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}
