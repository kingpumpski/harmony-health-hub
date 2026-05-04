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
import Dashboard from "./pages/Dashboard";
import PatientRegistration from "./pages/patients/PatientRegistration";
import PatientSearch from "./pages/patients/PatientSearch";
import PatientChat from "./pages/patients/PatientChat";
import PatientPortal from "./pages/PatientPortal";
import SystemLibrary from "./pages/admin/SystemLibrary";
import Triage from "./pages/Triage";
import Consultation from "./pages/Consultation";
import Ophthalmology from "./pages/Ophthalmology";
import Laboratory from "./pages/Laboratory";
import Pharmacy from "./pages/Pharmacy";
import Notifications from "./pages/Notifications";
import AdminUsers from "./pages/admin/AdminUsers";
import BulkUpload from "./pages/admin/BulkUpload";
import FeaturePage from "./pages/FeaturePage";
import SoundAlerts from "./pages/SoundAlerts";
import PublicHealthReports from "./pages/PublicHealthReports";
import RosterGenerator from "./pages/RosterGenerator";
import AIClinicalHub from "./pages/AIClinicalHub";
import Encounters from "./pages/Encounters";
import Billing from "./pages/Billing";
import Fertility from "./pages/Fertility";
import Telemedicine from "./pages/Telemedicine";
import Appointments from "./pages/Appointments";
import Dental from "./pages/Dental";
import ProcedureNotes from "./pages/ProcedureNotes";
import AnestheticAssessment from "./pages/AnestheticAssessment";
import TreatmentTemplates from "./pages/TreatmentTemplates";
import OutsideLabUploads from "./pages/OutsideLabUploads";
import CanteenMeals from "./pages/CanteenMeals";
import AIReportGenerator from "./pages/AIReportGenerator";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
      <AuthProvider>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <BrowserRouter>
            <Routes>
              <Route path="/" element={<Index />} />
              <Route path="/login" element={<Login />} />
              <Route element={<MainLayout />}>
                <Route path="/dashboard" element={<Dashboard />} />
                <Route path="/registration" element={<PatientRegistration />} />
                <Route path="/patients" element={<PatientSearch />} />
                <Route path="/patients/:patientId/chat" element={<PatientChat />} />
                <Route path="/patient-portal" element={<PatientPortal />} />

                {/* Workflow */}
                <Route path="/appointments" element={<Appointments />} />
                <Route path="/vitals" element={<Triage />} />
                <Route path="/consultation" element={<Consultation />} />
                <Route path="/encounters" element={<Encounters />} />
                <Route path="/ophthalmology" element={<Ophthalmology />} />

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
          </BrowserRouter>
        </TooltipProvider>
      </AuthProvider>
    </ThemeProvider>
  </QueryClientProvider>
);

export default App;
