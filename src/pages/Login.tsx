import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { HeartPulse, Eye, EyeOff, ArrowRight } from 'lucide-react';
import { UserRole } from '@/types';

const quickAccessRoles: { role: UserRole; label: string; color: string }[] = [
  { role: 'front_desk', label: 'Front Desk', color: 'bg-info' },
  { role: 'practitioner', label: 'Doctor', color: 'bg-primary' },
  { role: 'nurse', label: 'Nurse', color: 'bg-success' },
  { role: 'lab_technician', label: 'Lab Tech', color: 'bg-warning' },
  { role: 'pharmacist', label: 'Pharmacist', color: 'bg-accent' },
  { role: 'accountant', label: 'Accounts', color: 'bg-fertility' },
];

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const { login, switchRole } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    try {
      await login(email, password);
      navigate('/dashboard');
    } catch (error) {
      console.error('Login failed:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const handleQuickAccess = (role: UserRole) => {
    switchRole(role);
    navigate('/dashboard');
  };

  return (
    <div className="min-h-screen flex">
      {/* Left Panel - Branding */}
      <div className="hidden lg:flex lg:w-1/2 bg-gradient-to-br from-sidebar to-sidebar-accent relative overflow-hidden">
        <div className="absolute inset-0 bg-[url('data:image/svg+xml,%3Csvg%20width%3D%2260%22%20height%3D%2260%22%20viewBox%3D%220%200%2060%2060%22%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%3E%3Cg%20fill%3D%22none%22%20fill-rule%3D%22evenodd%22%3E%3Cg%20fill%3D%22%23ffffff%22%20fill-opacity%3D%220.03%22%3E%3Cpath%20d%3D%22M36%2034v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6%2034v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6%204V0H4v4H0v2h4v4h2V6h4V4H6z%22%2F%3E%3C%2Fg%3E%3C%2Fg%3E%3C%2Fsvg%3E')] opacity-50" />
        
        <div className="relative z-10 flex flex-col justify-center px-12 py-16">
          <div className="flex items-center gap-4 mb-12">
            <div className="w-16 h-16 rounded-2xl bg-sidebar-primary flex items-center justify-center shadow-lg">
              <HeartPulse className="w-10 h-10 text-sidebar-primary-foreground" />
            </div>
            <div>
              <h1 className="text-4xl font-heading font-bold text-sidebar-foreground">MediCare Pro</h1>
              <p className="text-sidebar-foreground/70">Health Management System</p>
            </div>
          </div>

          <div className="space-y-8">
            <div>
              <h2 className="text-2xl font-heading font-semibold text-sidebar-foreground mb-4">
                Comprehensive Healthcare Delivery
              </h2>
              <p className="text-sidebar-foreground/70 leading-relaxed">
                An integrated health management platform designed to streamline patient care, 
                optimize workflows, and enhance clinical outcomes across all departments.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4">
              {[
                'Patient Management',
                'Lab & Diagnostics',
                'Pharmacy & Billing',
                'Fertility Services',
                'Inpatient Care',
                'AI-Powered Insights',
              ].map((feature) => (
                <div key={feature} className="flex items-center gap-2 text-sidebar-foreground/80">
                  <div className="w-2 h-2 rounded-full bg-sidebar-primary" />
                  <span className="text-sm">{feature}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Right Panel - Login Form */}
      <div className="flex-1 flex items-center justify-center p-8 bg-background">
        <div className="w-full max-w-md">
          {/* Mobile Logo */}
          <div className="lg:hidden flex items-center gap-3 mb-8">
            <div className="w-12 h-12 rounded-xl bg-primary flex items-center justify-center">
              <HeartPulse className="w-7 h-7 text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-2xl font-heading font-bold">MediCare Pro</h1>
              <p className="text-sm text-muted-foreground">Health Management System</p>
            </div>
          </div>

          <div className="card-medical p-8">
            <div className="mb-8">
              <h2 className="text-2xl font-heading font-bold">Welcome back</h2>
              <p className="text-muted-foreground mt-2">Sign in to access your dashboard</p>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">
              <div>
                <label className="block text-sm font-medium mb-2">Email Address</label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Enter your email"
                  className="input-medical"
                />
              </div>

              <div>
                <label className="block text-sm font-medium mb-2">Password</label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Enter your password"
                    className="input-medical pr-10"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              <div className="flex items-center justify-between text-sm">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input type="checkbox" className="rounded border-input" />
                  <span>Remember me</span>
                </label>
                <button type="button" className="text-primary hover:underline">
                  Forgot password?
                </button>
              </div>

              <button
                type="submit"
                disabled={isLoading}
                className="btn-primary w-full"
              >
                {isLoading ? 'Signing in...' : 'Sign In'}
                <ArrowRight className="w-4 h-4" />
              </button>
            </form>
          </div>

          {/* Quick Access for Demo */}
          <div className="mt-8">
            <p className="text-center text-sm text-muted-foreground mb-4">
              Demo Quick Access
            </p>
            <div className="grid grid-cols-3 gap-2">
              {quickAccessRoles.map(({ role, label, color }) => (
                <button
                  key={role}
                  onClick={() => handleQuickAccess(role)}
                  className="card-medical p-3 text-center hover:shadow-md transition-all group"
                >
                  <div className={`w-8 h-8 rounded-lg ${color} mx-auto mb-2 group-hover:scale-110 transition-transform`} />
                  <span className="text-xs font-medium">{label}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
