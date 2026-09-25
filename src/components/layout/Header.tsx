import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { useNavigate, Link, useLocation } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { Bell, Search, Moon, Sun, AlertTriangle, AlertCircle, Info, CheckCircle2, Settings, LogOut, UserRound, Clock3, Menu } from "lucide-react";
import { cn } from "@/lib/utils";
import { UserRole } from "@/types";
import { searchPatients } from "@/lib/healthApi";

const roleLabels: Record<UserRole, string> = {
  admin: "Administrator", practitioner: "Dr.", nurse: "Nurse", midwife: "Midwife", specialist_nurse: "Specialist Nurse",
  radiologist: "Radiologist", lab_technician: "Lab Technician", pharmacist: "Pharmacist", accountant: "Accounts Officer",
  front_desk: "Front Desk Officer", canteen: "Canteen Staff", patient: "Patient", it_admin: "IT Admin",
};

interface HeaderProps { onMenu?: () => void }
interface NotifRow { id: string; title: string; message: string; severity: string; category: string | null; link: string | null; is_read: boolean; created_at: string }
const sevIcon = (s: string) => s === "critical" ? <AlertTriangle className="h-4 w-4 text-critical animate-pulse" /> : s === "warning" ? <AlertCircle className="h-4 w-4 text-warning" /> : s === "success" ? <CheckCircle2 className="h-4 w-4 text-success" /> : <Info className="h-4 w-4 text-info" />;

export default function Header({ onMenu }: HeaderProps) {
  const { theme, setTheme } = useTheme();
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [searchTerm, setSearchTerm] = useState("");
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [showNotifications, setShowNotifications] = useState(false);
  const [showAccount, setShowAccount] = useState(false);
  const [notifications] = useState<NotifRow[]>([]);
  const unread = 0;
  const hasCritical = false;
  const greeting = `Welcome ${roleLabels[user?.role ?? "patient"]} ${user?.lastName || user?.firstName || ""}`.trim();
  const pageLabel = location.pathname.split("/").filter(Boolean).filter(segment => !/^[0-9a-f-]{8,}$/i.test(segment)).pop()?.replace(/-/g, " ").replace(/\b\w/g, letter => letter.toUpperCase()) || "Dashboard";

  useEffect(() => {
    if (user?.role === "it_admin") { setSearchResults([]); setIsSearching(false); return; }
    const query = searchTerm.trim();
    if (!query) { setSearchResults([]); setIsSearching(false); return; }
    let active = true;
    setIsSearching(true);
    const timer = window.setTimeout(() => {
      void searchPatients(query).then(results => { if (active) setSearchResults(results.slice(0, 8)); }).finally(() => { if (active) setIsSearching(false); });
    }, 250);
    return () => { active = false; window.clearTimeout(timer); };
  }, [searchTerm, user?.role]);

  if (!user) return null;

  return (
    <header className="sticky top-0 z-30 border-b border-border/80 bg-card/95 px-3 py-2.5 shadow-sm backdrop-blur supports-[backdrop-filter]:bg-card/80 sm:px-5 lg:px-7">
      <div className="flex min-h-11 items-center gap-3">
        <button type="button" onClick={onMenu} className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border bg-background text-muted-foreground hover:bg-muted hover:text-foreground md:hidden" aria-label="Open navigation"><Menu className="h-5 w-5" /></button>
        <div className="hidden min-w-0 shrink-0 sm:block sm:w-48 lg:w-56">
          <p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-primary">Harmony Health Hub</p>
          <div className="flex items-center gap-2"><h2 className="truncate text-sm font-semibold">{pageLabel}</h2><span className="text-muted-foreground/40">/</span><span className="truncate text-xs text-muted-foreground">{greeting}</span></div>
        </div>

        <div className="min-w-0 flex-1">
          <form onSubmit={e => e.preventDefault()} className="relative mx-auto max-w-2xl">
            <Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            {user.role !== "it_admin" && <input value={searchTerm} onChange={e => setSearchTerm(e.target.value)} placeholder="Search patients by name, code or phone…" className="input-medical h-10 rounded-xl bg-background/80 pl-10 pr-20" />}
            {user.role !== "it_admin" && searchTerm.trim() && (isSearching || searchResults.length > 0) && <div className="absolute left-0 right-0 z-40 mt-2 overflow-hidden rounded-2xl border border-border bg-card shadow-elevated"><div className="max-h-72 overflow-auto p-2">
              {searchResults.slice(0, 8).map(r => <Link key={r.id} to={`/patients/${r.id}/chat`} onClick={() => { setSearchResults([]); setSearchTerm(""); }} className="block rounded-xl p-3 hover:bg-muted/60"><p className="text-sm font-medium">{r.fullName}</p><p className="text-xs text-muted-foreground">{r.patientId} · {r.phone || "no phone"}</p></Link>)}
              {!isSearching && searchResults.length === 0 && <p className="p-4 text-center text-sm text-muted-foreground">No matching patient records found.</p>}
            </div></div>}
            {isSearching && <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">Searching…</span>}
          </form>
        </div>

        <div className="flex shrink-0 items-center gap-1 sm:gap-2">
          <span className="hidden xl:inline-flex items-center gap-2 rounded-full border border-border bg-background px-3 py-1.5 text-xs font-medium text-muted-foreground"><span className="h-1.5 w-1.5 rounded-full bg-success" />{roleLabels[user.role]}</span>
          <div className="relative">
            <button type="button" onClick={() => setShowNotifications(v => !v)} className={cn("relative rounded-xl p-2 hover:bg-muted", hasCritical && "animate-pulse")} aria-label="Notifications">
              <Bell className={cn("h-5 w-5", hasCritical ? "text-critical" : "text-muted-foreground")} />
              {unread > 0 && <span className="absolute -right-0.5 -top-0.5 flex min-h-[18px] min-w-[18px] items-center justify-center rounded-full bg-critical px-1 text-[10px] font-bold text-critical-foreground">{unread > 9 ? "9+" : unread}</span>}
            </button>
            {showNotifications && <div className="absolute right-0 z-50 mt-2 w-[min(24rem,calc(100vw-2rem))] overflow-hidden rounded-2xl border border-border bg-card shadow-elevated">
              <div className="flex items-center justify-between border-b p-4"><h3 className="font-semibold">Notifications</h3><Link to="/notifications" onClick={() => setShowNotifications(false)} className="text-xs text-primary">View all</Link></div>
              <div className="max-h-96 overflow-y-auto">{notifications.length === 0 ? <p className="p-8 text-center text-sm text-muted-foreground">No notifications yet.</p> : notifications.map(n => <div key={n.id} className={cn("flex cursor-pointer gap-3 border-b p-3 last:border-0 hover:bg-muted/50", !n.is_read && "bg-primary/5")} onClick={() => { if (n.link) { setShowNotifications(false); navigate(n.link); } }}>{sevIcon(n.severity)}<div className="min-w-0 flex-1"><p className="text-sm font-medium">{n.title}</p><p className="line-clamp-2 text-xs text-muted-foreground">{n.message}</p></div></div>)}</div>
            </div>}
          </div>
          <button type="button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")} className="rounded-xl p-2 hover:bg-muted" aria-label="Toggle theme">{theme === "dark" ? <Sun className="h-5 w-5 text-muted-foreground" /> : <Moon className="h-5 w-5 text-muted-foreground" />}</button>
          <div className="relative">
            <button type="button" onClick={() => setShowAccount(v => !v)} className="rounded-xl p-1.5 hover:bg-muted" aria-label="Account menu"><div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">{(user.firstName?.[0] || "U").toUpperCase()}{(user.lastName?.[0] || "").toUpperCase()}</div></button>
            {showAccount && <div className="absolute right-0 z-50 mt-2 w-64 overflow-hidden rounded-2xl border border-border bg-card shadow-elevated">
              <div className="border-b p-4"><p className="text-sm font-semibold">{user.firstName} {user.lastName}</p><p className="truncate text-xs text-muted-foreground">{user.email}</p><p className="mt-1 text-xs text-primary">{roleLabels[user.role]}</p></div>
              <div className="p-2">
                <Link to="/profile" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><UserRound className="h-4 w-4" />My profile & workspace</Link>
                {user.role === "admin" && <><Link to="/admin/settings" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><Settings className="h-4 w-4" />System settings</Link><Link to="/admin/shifts" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><Clock3 className="h-4 w-4" />Staff shifts</Link></>}
                <Link to="/notifications" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><Bell className="h-4 w-4" />Notifications</Link>
                <button type="button" onClick={() => void logout()} className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-critical hover:bg-critical/10"><LogOut className="h-4 w-4" />Sign out</button>
              </div>
            </div>}
          </div>
        </div>
      </div>
    </header>
  );
}
