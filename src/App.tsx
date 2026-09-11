import { lazy, Suspense } from "react";
import { ThemeProvider } from "next-themes";
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { AuthProvider } from "@/contexts/AuthContext";
import MainLayout from "@/components/layout/MainLayout";
import Index from "./pages/Index";
import Login from "./pages/Login";

const Dashboard = lazy(() => import("./pages/Dashboard"));
const PatientRegistration = lazy(() => import("./pages/patients/PatientRegistration"));
const PatientSearch = lazy(() => import("./pages/patients/PatientSearch"));
const PatientHub = lazy(() => import("./pages/patients/PatientHub"));
const PatientChat = lazy(() => import("./pages/patients/PatientChat"));
const PatientPortal = lazy(() => import("./pages/PatientPortal"));
const SystemLibrary = lazy(() => import("./pages/admin/SystemLibrary"));
const Triage = lazy(() => import("./pages/Triage"));
const Consultation = lazy(() => import("./pages/Consultation"));
const Ophthalmology = lazy(() => import("./pages/Ophthalmology"));
const Laboratory = lazy(() => import("./pages/Laboratory"));
const Pharmacy = lazy(() => import("./pages/Pharmacy"));
const Notifications = lazy(() => import("./pages/Notifications"));
const AdminUsers = lazy(() => import("./pages/admin/AdminUsers"));
const BulkUpload = lazy(() => import("./pages/admin/BulkUpload"));
const FeaturePage = lazy(() => import("./pages/FeaturePage"));
const SoundAlerts = lazy(() => import("./pages/SoundAlerts"));
const PublicHealthReports = lazy(() => import("./pages/PublicHealthReports"));
const RosterGenerator = lazy(() => import("./pages/RosterGenerator"));
const AIClinicalHub = lazy(() => import("./pages/AIClinicalHub"));
const Encounters = lazy(() => import("./pages/Encounters"));
const Billing = lazy(() => import("./pages/Billing"));
const Fertility = lazy(() => import("./pages/Fertility"));
const Telemedicine = lazy(() => import("./pages/Telemedicine"));
const Appointments = lazy(() => import("./pages/Appointments"));
const Dental = lazy(() => import("./pages/Dental"));
const ProcedureNotes = lazy(() => import("./pages/ProcedureNotes"));
const AnestheticAssessment = lazy(() => import("./pages/AnestheticAssessment"));
const TreatmentTemplates = lazy(() => import("./pages/TreatmentTemplates"));
const OutsideLabUploads = lazy(() => import("./pages/OutsideLabUploads"));
const CanteenMeals = lazy(() => import("./pages/CanteenMeals"));
const AIReportGenerator = lazy(() => import("./pages/AIReportGenerator"));
const AccountsApprovals = lazy(() => import("./pages/AccountsApprovals"));
const NotFound = lazy(() => import("./pages/NotFound"));

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: false,
      retry: 1,
    },
  },
});

const PageFallback = () => (
  <div className="flex items-center justify-center p-12 text-sm text-muted-foreground">Loading…</div>
);

const App = () => (
  <QueryClientProvider client={queryClient}>
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
      <AuthProvider>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <BrowserRouter>
            <Suspense fallback={<PageFallback />}>
              <Routes>
                <Route path="/" element={<Index />} />
                <Route path="/login" element={<Login />} />
                <Route element={<MainLayout />}>
                  <Route path="/dashboard" element={<Dashboard />} />
                  <Route path="/registration" element={<PatientRegistration />} />
                  <Route path="/patients" element={<PatientSearch />} />
                  <Route path="/patients/:patientId" element={<PatientHub />} />
                  <Route path="/patients/:patientId/chat" element={<PatientChat />} />
                  <Route path="/patient-portal" element={<PatientPortal />} />

                  {/* Workflow */}
                  <Route path="/appointments" element={<Appointments />} />
                  <Route path="/vitals" element={<Triage />} />
                  <Route path="/consultation" element={<Consultation />} />
                  <Route path="/encounters" element={<Encounters />} />
                  <Route path="/ophthalmology" element={<Ophthalmology />} />
                  <Route path="/accounts-approvals" element={<AccountsApprovals />} />

                  {/* Lab */}
                  <Route path="/laboratory" element={<Laboratory />} />
                  <Route path="/lab-results" element={<Laboratory />} />
                  <Route path="/lab-requests" element={<Laboratory />} />
                  <Route path="/results-entry" element={<Laboratory />} />

                  {/* Pharmacy */}
                  <Route path="/pharmacy" element={<Pharmacy />} />
                  <Route path="/medications" element={<Pharmacy />} />
                  <Route path="/dispensing" element={<Pharmacy />} />
                  <Route path="/inventory" element={<Pharmacy />} />
                  <Route path="/stock-alerts" element={<SoundAlerts />} />
                  <Route path="/sound-alerts" element={<SoundAlerts />} />

                  {/* Records */}
                  <Route path="/records" element={<FeaturePage title="Medical Records" description="Review patient charts, documents, and historical visits." />} />
                  <Route path="/inpatients" element={<FeaturePage title="Inpatient Care" description="Manage admissions, ward allocation, and patient monitoring." />} />
                  <Route path="/admissions" element={<FeaturePage title="Admissions" description="Coordinate admissions, transfers, and bed assignments." />} />
                  <Route path="/monitoring" element={<FeaturePage title="Monitoring" description="Track vital sign trends and nursing rounds." />} />
                  <Route path="/maternity" element={<FeaturePage title="Maternity Services" description="Support maternity care workflows and patient tracking." />} />

                  {/* Billing & Telemedicine & Fertility */}
                  <Route path="/billing" element={<Billing />} />
                  <Route path="/invoices" element={<Billing />} />
                  <Route path="/insurance" element={<Billing />} />
                  <Route path="/financial-reports" element={<Billing />} />
                  <Route path="/telemedicine" element={<Telemedicine />} />
                  <Route path="/fertility" element={<Fertility />} />

                  {/* Specialty clinical */}
                  <Route path="/dental" element={<Dental />} />
                  <Route path="/procedures" element={<ProcedureNotes />} />
                  <Route path="/anesthesia" element={<AnestheticAssessment />} />
                  <Route path="/treatment-templates" element={<TreatmentTemplates />} />
                  <Route path="/outside-lab" element={<OutsideLabUploads />} />
                  <Route path="/ai-report" element={<AIReportGenerator />} />

                  {/* Canteen */}
                  <Route path="/menu" element={<CanteenMeals />} />
                  <Route path="/orders" element={<CanteenMeals />} />
                  <Route path="/dietary-plans" element={<CanteenMeals />} />

                  {/* Reports & AI */}
                  <Route path="/reports" element={<PublicHealthReports />} />
                  <Route path="/public-health" element={<PublicHealthReports />} />
                  <Route path="/roster" element={<RosterGenerator />} />
                  <Route path="/ai-clinical" element={<AIClinicalHub />} />

                  {/* Admin */}
                  <Route path="/admin/users" element={<AdminUsers />} />
                  <Route path="/admin/system" element={<SystemLibrary />} />
                  <Route path="/admin/roles" element={<AdminUsers />} />
                  <Route path="/admin/settings" element={<FeaturePage title="System Settings" description="Administer application configuration and security settings." />} />
                  <Route path="/admin/bulk-upload" element={<BulkUpload />} />
                  <Route path="/admin/logs" element={<FeaturePage title="System Logs" description="Audit logs for compliance and traceability." />} />

                  <Route path="/notifications" element={<Notifications />} />
                </Route>
                <Route path="*" element={<NotFound />} />
              </Routes>
            </Suspense>
          </BrowserRouter>
        </TooltipProvider>
      </AuthProvider>
    </ThemeProvider>
  </QueryClientProvider>
);

export default App;
