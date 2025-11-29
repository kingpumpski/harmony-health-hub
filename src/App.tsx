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
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
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
              <Route path="/patients" element={<Dashboard />} />
              <Route path="/appointments" element={<Dashboard />} />
              <Route path="/encounters" element={<Dashboard />} />
              <Route path="/records" element={<Dashboard />} />
              <Route path="/lab-results" element={<Dashboard />} />
              <Route path="/lab-requests" element={<Dashboard />} />
              <Route path="/results-entry" element={<Dashboard />} />
              <Route path="/reports" element={<Dashboard />} />
              <Route path="/inpatients" element={<Dashboard />} />
              <Route path="/vitals" element={<Dashboard />} />
              <Route path="/medications" element={<Dashboard />} />
              <Route path="/nursing-notes" element={<Dashboard />} />
              <Route path="/dispensing" element={<Dashboard />} />
              <Route path="/inventory" element={<Dashboard />} />
              <Route path="/stock-alerts" element={<Dashboard />} />
              <Route path="/billing" element={<Dashboard />} />
              <Route path="/invoices" element={<Dashboard />} />
              <Route path="/insurance" element={<Dashboard />} />
              <Route path="/financial-reports" element={<Dashboard />} />
              <Route path="/maternity" element={<Dashboard />} />
              <Route path="/admissions" element={<Dashboard />} />
              <Route path="/monitoring" element={<Dashboard />} />
              <Route path="/menu" element={<Dashboard />} />
              <Route path="/orders" element={<Dashboard />} />
              <Route path="/dietary-plans" element={<Dashboard />} />
              <Route path="/fertility" element={<Dashboard />} />
              <Route path="/admin/users" element={<Dashboard />} />
              <Route path="/admin/roles" element={<Dashboard />} />
              <Route path="/admin/settings" element={<Dashboard />} />
              <Route path="/admin/logs" element={<Dashboard />} />
              <Route path="/notifications" element={<Dashboard />} />
            </Route>
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </AuthProvider>
  </QueryClientProvider>
);

export default App;
