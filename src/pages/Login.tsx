import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { HeartPulse, Eye, EyeOff, ArrowRight } from 'lucide-react';
import { toast } from '@/hooks/use-toast';

export default function Login() {
  const [mode, setMode] = useState<'signin' | 'signup'>('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const { login, signUp, isAuthenticated, loading } = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (!loading && isAuthenticated) navigate('/dashboard', { replace: true });
  }, [isAuthenticated, loading, navigate]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    try {
      if (mode === 'signin') {
        await login(email, password);
        toast({ title: 'Welcome back', description: 'Signed in successfully.' });
      } else {
        if (!firstName.trim() || !lastName.trim()) {
          toast({ title: 'Missing details', description: 'Please enter your first and last name.', variant: 'destructive' });
          return;
        }
        await signUp(email, password, firstName.trim(), lastName.trim());
        toast({ title: 'Account created', description: 'You are now signed in as a patient.' });
      }
      navigate('/dashboard');
    } catch (err: any) {
      toast({
        title: mode === 'signin' ? 'Sign in failed' : 'Sign up failed',
        description: err?.message ?? 'Please try again.',
        variant: 'destructive',
      });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex">
      <div className="hidden lg:flex lg:w-1/2 bg-gradient-to-br from-sidebar to-sidebar-accent relative overflow-hidden">
        <div className="relative z-10 flex flex-col justify-center px-12 py-16">
          <div className="flex items-center gap-4 mb-12">
            <div className="w-16 h-16 rounded-2xl bg-sidebar-primary flex items-center justify-center shadow-lg">
              <HeartPulse className="w-10 h-10 text-sidebar-primary-foreground" />
            </div>
            <div>
              <h1 className="text-4xl font-heading font-bold text-sidebar-foreground">Harmony Health Hub</h1>
              <p className="text-sidebar-foreground/70">Healthcare Management System</p>
            </div>
          </div>

          <div className="space-y-8">
            <div>
              <h2 className="text-2xl font-heading font-semibold text-sidebar-foreground mb-4">
                Comprehensive Healthcare Delivery
              </h2>
              <p className="text-sidebar-foreground/70 leading-relaxed">
                An integrated platform for hospitals and fertility clinics — patient lifecycle, clinical
                encounters, labs, pharmacy, billing, fertility cycles, and telemedicine in one place.
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4">
              {[
                'Patient Management',
                'Clinical Encounters',
                'Lab & Diagnostics',
                'Pharmacy & Billing',
                'Fertility Services',
                'Telemedicine',
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

      <div className="flex-1 flex items-center justify-center p-8 bg-background">
        <div className="w-full max-w-md">
          <div className="lg:hidden flex items-center gap-3 mb-8">
            <div className="w-12 h-12 rounded-xl bg-primary flex items-center justify-center">
              <HeartPulse className="w-7 h-7 text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-2xl font-heading font-bold">Harmony Health Hub</h1>
              <p className="text-sm text-muted-foreground">Healthcare Management System</p>
            </div>
          </div>

          <div className="card-medical p-8">
            <div className="mb-8">
              <h2 className="text-2xl font-heading font-bold">
                {mode === 'signin' ? 'Welcome back' : 'Create patient account'}
              </h2>
              <p className="text-muted-foreground mt-2">
                {mode === 'signin'
                  ? 'Sign in to access your dashboard'
                  : 'Patients can self-register. Staff accounts are created by an administrator.'}
              </p>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">
              {mode === 'signup' && (
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-sm font-medium mb-2">First name</label>
                    <input
                      type="text"
                      value={firstName}
                      onChange={(e) => setFirstName(e.target.value)}
                      className="input-medical"
                      required
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium mb-2">Last name</label>
                    <input
                      type="text"
                      value={lastName}
                      onChange={(e) => setLastName(e.target.value)}
                      className="input-medical"
                      required
                    />
                  </div>
                </div>
              )}

              <div>
                <label className="block text-sm font-medium mb-2">Email Address</label>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  className="input-medical"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium mb-2">Password</label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="At least 8 characters"
                    className="input-medical pr-10"
                    minLength={8}
                    required
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

              <button type="submit" disabled={isLoading} className="btn-primary w-full">
                {isLoading ? 'Please wait…' : mode === 'signin' ? 'Sign In' : 'Create account'}
                <ArrowRight className="w-4 h-4" />
              </button>
            </form>

            <p className="text-sm text-muted-foreground text-center mt-6">
              {mode === 'signin' ? "Don't have an account? " : 'Already registered? '}
              <button
                type="button"
                onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}
                className="text-primary hover:underline font-medium"
              >
                {mode === 'signin' ? 'Sign up as a patient' : 'Sign in'}
              </button>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
