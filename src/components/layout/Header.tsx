import { useEffect, useState } from 'react';
import { useTheme } from 'next-themes';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { Bell, Search, Moon, Sun, AlertTriangle, AlertCircle, Info, CheckCircle2 } from 'lucide-react';
import { cn } from '@/lib/utils';
import { UserRole } from '@/types';
import { searchPatients } from '@/lib/healthApi';
import { supabase } from '@/integrations/supabase/client';

const roleLabels: Record<UserRole, string> = {
  admin: 'Administrator',
  practitioner: 'Practitioner',
  nurse: 'Nurse',
  midwife: 'Midwife',
  lab_technician: 'Lab Technician',
  pharmacist: 'Pharmacist',
  accountant: 'Accountant',
  front_desk: 'Front Desk',
  canteen: 'Canteen Staff',
  patient: 'Patient',
};

interface NotifRow {
  id: string; title: string; message: string; severity: string; category: string | null;
  link: string | null; is_read: boolean; created_at: string;
}

const sevIcon = (sev: string) => {
  if (sev === 'critical') return <AlertTriangle className="w-4 h-4 text-critical animate-pulse" />;
  if (sev === 'warning') return <AlertCircle className="w-4 h-4 text-warning" />;
  if (sev === 'success') return <CheckCircle2 className="w-4 h-4 text-success" />;
  return <Info className="w-4 h-4 text-info" />;
};

export default function Header() {
  const { theme, setTheme } = useTheme();
  const { user } = useAuth();
  const navigate = useNavigate();
  const [searchTerm, setSearchTerm] = useState('');
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [showNotifications, setShowNotifications] = useState(false);
  const [notifications, setNotifications] = useState<NotifRow[]>([]);

  const unread = notifications.filter((n) => !n.is_read).length;
  const hasCritical = notifications.some((n) => !n.is_read && n.severity === 'critical');

  const loadNotifications = async () => {
    const { data } = await supabase
      .from('notifications').select('*')
      .order('created_at', { ascending: false }).limit(20);
    setNotifications(data ?? []);
  };

  useEffect(() => {
    if (!user) return;
    loadNotifications();
    const channel = supabase
      .channel('header-notif')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => loadNotifications())
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user?.id]);

  // Audio cue for new critical alerts
  useEffect(() => {
    if (!hasCritical) return;
    const beep = new Audio('data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2teleQ4fk9/qvYIwA2Orzdy/dCANgtnv28RMCx/I+fjObiYNvPT34oM7ChLe//jljT4JGf//+NiVRg4a//7/wZ1ODSQG///cpVgXMhD/9t6lYhg7DP7v2ZhnFjER/+fbnW0ZOg7//dWiaR8yDP/z1KBtJTkN+fjWoW8pMg793tSdcSUoEPz436J2IykQ//baoHUlKBD///emeicuE/7326F3IyYS/fnbpnwnKBL///2me');
    beep.volume = 0.3;
    beep.play().catch(() => {});
  }, [hasCritical]);

  const markRead = async (id: string) => {
    await supabase.from('notifications').update({ is_read: true }).eq('id', id);
  };

  if (!user) return null;

  return (
    <header className="sticky top-0 z-30 h-16 bg-card border-b border-border px-6 flex items-center justify-between">
      {/* Search */}
      <div className="flex-1 max-w-md">
        <form
          onSubmit={async (event) => {
            event.preventDefault();
            if (!searchTerm.trim()) return;
            setIsSearching(true);
            const results = await searchPatients(searchTerm.trim());
            setSearchResults(results);
            setIsSearching(false);
          }}
          className="relative"
        >
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <input
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            type="text"
            placeholder="Search patients by name, code, phone..."
            className="input-medical pl-10 w-full"
          />
          {searchResults.length > 0 && (
            <div className="absolute left-0 right-0 z-20 mt-2 rounded-2xl border border-border bg-card p-3 shadow-elevated">
              <div className="space-y-2 max-h-72 overflow-auto">
                {searchResults.slice(0, 8).map((result) => (
                  <Link
                    key={result.id}
                    to={`/patients/${result.id}/chat`}
                    onClick={() => { setSearchResults([]); setSearchTerm(''); }}
                    className="block rounded-xl border border-border p-3 hover:bg-muted/50 transition-colors"
                  >
                    <p className="font-medium text-sm">{result.fullName}</p>
                    <p className="text-xs text-muted-foreground">{result.patientId} · {result.phone || 'no phone'}</p>
                  </Link>
                ))}
              </div>
            </div>
          )}
          {isSearching && <div className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground text-xs">Searching…</div>}
        </form>
      </div>

      <div className="flex items-center gap-3">
        <span className="hidden md:inline text-xs text-muted-foreground">
          Signed in as <span className="font-medium text-foreground">{roleLabels[user.role]}</span>
        </span>

        {/* Notifications */}
        <div className="relative">
          <button
            onClick={() => setShowNotifications((v) => !v)}
            className={cn(
              'relative p-2 rounded-lg hover:bg-muted transition-colors',
              hasCritical && 'animate-pulse',
            )}
          >
            <Bell className={cn('w-5 h-5', hasCritical ? 'text-critical' : 'text-muted-foreground')} />
            {unread > 0 && (
              <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] text-[10px] font-bold rounded-full bg-critical text-critical-foreground flex items-center justify-center px-1">
                {unread > 9 ? '9+' : unread}
              </span>
            )}
          </button>

          {showNotifications && (
            <div className="absolute right-0 mt-2 w-96 bg-card rounded-lg shadow-elevated border border-border animate-scale-in z-40">
              <div className="p-3 border-b border-border flex items-center justify-between">
                <h3 className="font-semibold">Notifications</h3>
                <Link to="/notifications" onClick={() => setShowNotifications(false)} className="text-xs text-primary hover:underline">View all</Link>
              </div>
              <div className="max-h-96 overflow-y-auto">
                {notifications.length === 0 && (
                  <p className="text-sm text-muted-foreground text-center p-6">No notifications yet.</p>
                )}
                {notifications.map((n) => {
                  const Inner = (
                    <div
                      className={cn(
                        'p-3 border-b border-border last:border-0 hover:bg-muted/50 cursor-pointer transition-colors flex gap-3',
                        !n.is_read && 'bg-primary/5',
                        n.severity === 'critical' && 'border-l-2 border-l-critical',
                      )}
                      onClick={() => {
                        if (!n.is_read) markRead(n.id);
                        if (n.link) { setShowNotifications(false); navigate(n.link); }
                      }}
                    >
                      {sevIcon(n.severity)}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-start justify-between gap-2">
                          <p className="font-medium text-sm">{n.title}</p>
                          <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                            {new Date(n.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        </div>
                        <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{n.message}</p>
                      </div>
                    </div>
                  );
                  return <div key={n.id}>{Inner}</div>;
                })}
              </div>
            </div>
          )}
        </div>

        <button
          onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          className="p-2 rounded-lg hover:bg-muted transition-colors"
          aria-label="Toggle theme"
        >
          {theme === 'dark' ? <Sun className="w-5 h-5 text-muted-foreground" /> : <Moon className="w-5 h-5 text-muted-foreground" />}
        </button>
      </div>
    </header>
  );
}
