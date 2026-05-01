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
import FeaturePage from "./pages/FeaturePage";
import SoundAlerts from "./pages/SoundAlerts";
import PublicHealthReports from "./pages/PublicHealthReports";
import RosterGenerator from "./pages/RosterGenerator";
import AIClinicalHub from "./pages/AIClinicalHub";
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
                <Route path="/appointments" element={<FeaturePage title="Appointments" description="Manage and monitor patient appointment schedules." />} />
              <Route path="/encounters" element={<FeaturePage title="Encounters" description="Document clinical encounters and consultation summaries." />} />
              <Route path="/records" element={<FeaturePage title="Medical Records" description="Review patient charts, documents, and historical visits." />} />
              <Route path="/lab-results" element={<Laboratory />} />
              <Route path="/lab-requests" element={<Laboratory />} />
              <Route path="/results-entry" element={<Laboratory />} />
              <Route path="/reports" element={<PublicHealthReports />} />
              <Route path="/inpatients" element={<FeaturePage title="Inpatient Care" description="Manage admissions, ward allocation, and patient monitoring." />} />
              <Route path="/vitals" element={<Triage />} />
              <Route path="/consultation" element={<Consultation />} />
              <Route path="/ophthalmology" element={<Ophthalmology />} />
              <Route path="/medications" element={<Pharmacy />} />
              <Route path="/dispensing" element={<Pharmacy />} />
              <Route path="/inventory" element={<Pharmacy />} />
              <Route path="/stock-alerts" element={<SoundAlerts />} />
              <Route path="/sound-alerts" element={<SoundAlerts />} />
              <Route path="/billing" element={<FeaturePage title="Billing" description="Process invoices, payments, and insurance claims." />} />
              <Route path="/invoices" element={<FeaturePage title="Invoices" description="Generate and review billing invoices." />} />
              <Route path="/insurance" element={<FeaturePage title="Insurance" description="Manage insurance providers, claims and approvals." />} />
              <Route path="/financial-reports" element={<FeaturePage title="Financial Reports" description="View finance dashboards and audit summaries." />} />
              <Route path="/maternity" element={<FeaturePage title="Maternity Services" description="Support maternity care workflows and patient tracking." />} />
              <Route path="/admissions" element={<FeaturePage title="Admissions" description="Coordinate admissions, transfers, and bed assignments." />} />
              <Route path="/monitoring" element={<FeaturePage title="Monitoring" description="Track vital sign trends and nursing rounds." />} />
              <Route path="/menu" element={<FeaturePage title="Menu" description="Manage facility food services and dietary plans." />} />
              <Route path="/orders" element={<FeaturePage title="Orders" description="Process internal and external supply orders." />} />
              <Route path="/dietary-plans" element={<FeaturePage title="Dietary Plans" description="Plan meals and nutrition schedules for patients." />} />
              <Route path="/fertility" element={<FeaturePage title="Fertility Services" description="Support fertility workflows and treatment planning." />} />
              <Route path="/admin/users" element={<AdminUsers />} />
              <Route path="/admin/system" element={<SystemLibrary />} />
              <Route path="/admin/roles" element={<FeaturePage title="Role Management" description="Configure role-based access and permissions." />} />
              <Route path="/admin/settings" element={<FeaturePage title="System Settings" description="Administer application configuration and security settings." />} />
              <Route path="/admin/logs" element={<FeaturePage title="System Logs" description="Audit logs for compliance and traceability." />} />
              <Route path="/notifications" element={<Notifications />} />
              <Route path="/sound-alerts" element={<SoundAlerts />} />
              <Route path="/public-health" element={<PublicHealthReports />} />
              <Route path="/roster" element={<RosterGenerator />} />
              <Route path="/ai-clinical" element={<AIClinicalHub />} />
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
