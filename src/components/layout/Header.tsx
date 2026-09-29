import { useCallback, useEffect, useRef, useState } from "react";
import { useTheme } from "next-themes";
import { useNavigate, Link, useLocation } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { Bell, Search, Moon, Sun, AlertTriangle, AlertCircle, Info, CheckCircle2, Settings, LogOut, UserRound, Clock3, Menu, X } from "lucide-react";
import { cn } from "@/lib/utils";
import { UserRole } from "@/types";
import { supabase } from "@/integrations/supabase/client";
import { searchGlobalWorkspace, type GlobalSearchResult } from "@/lib/globalWorkspaceSearch";
import { notificationSoundKind, playWorkflowSound } from "@/lib/workflowFeedback";

const roleLabels: Record<UserRole, string> = {
  admin: "Administrator", practitioner: "Dr.", nurse: "Nurse", midwife: "Midwife", specialist_nurse: "Specialist Nurse",
  radiologist: "Radiologist", radiology_technician: "Radiology Technician", lab_technician: "Lab Technician", pharmacist: "Pharmacist", accountant: "Accounts Officer",
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
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");
  const [searchResults, setSearchResults] = useState<GlobalSearchResult[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [showNotifications, setShowNotifications] = useState(false);
  const [showAccount, setShowAccount] = useState(false);
  const [notifications, setNotifications] = useState<NotifRow[]>([]);
  const [notificationAttention, setNotificationAttention] = useState(false);
  const notificationIdsRef = useRef<Set<string>>(new Set());
  const notificationInitializedRef = useRef(false);
  const searchContainerRef = useRef<HTMLDivElement>(null);
  const notificationContainerRef = useRef<HTMLDivElement>(null);
  const accountContainerRef = useRef<HTMLDivElement>(null);
  const db = supabase as any;

  const loadNotifications = useCallback(async () => {
    if (!user?.id || user.role === "it_admin") return;
    const [{ data }, { data: config }] = await Promise.all([
      db.rpc("get_workflow_notifications", { _limit: 30 }),
      db.from("facility_configuration").select("notification_sound_enabled").limit(1).maybeSingle(),
    ]);
    const soundEnabled = config?.notification_sound_enabled !== false;
    const rows = Array.isArray(data) ? data as NotifRow[] : [];
    const unreadRows = rows.filter((n) => !n.is_read);
    const previousIds = notificationIdsRef.current;
    const newUnread = unreadRows.filter((n) => !previousIds.has(n.id));
    if (notificationInitializedRef.current && newUnread.length > 0) {
      const newest = newUnread[0];
      if (soundEnabled) playWorkflowSound(notificationSoundKind(newest));
      setNotificationAttention(true);
    }
    const hadInitialized = notificationInitializedRef.current;
    notificationIdsRef.current = new Set(rows.map((n) => n.id));
    notificationInitializedRef.current = true;
    setNotifications(rows);
    if (!hadInitialized && unreadRows.length > 0) setNotificationAttention(true);
  }, [user?.id, user?.role]);

  const unread = notifications.filter((n) => !n.is_read).length;
  const hasCritical = notifications.some((n) => !n.is_read && ["critical", "warning", "high"].includes(String(n.severity).toLowerCase()));
  const pageLabel = location.pathname.split("/").filter(Boolean).filter(segment => !/^[0-9a-f-]{8,}$/i.test(segment)).pop()?.replace(/-/g, " ").replace(/\b\w/g, letter => letter.toUpperCase()) || "Dashboard";

  useEffect(() => {
    const handlePointerDown = (event: PointerEvent) => {
      const target = event.target as Node;
      if (searchContainerRef.current && !searchContainerRef.current.contains(target)) { setSearchOpen(false); setSearchTerm(""); setSearchResults([]); }
      if (notificationContainerRef.current && !notificationContainerRef.current.contains(target)) setShowNotifications(false);
      if (accountContainerRef.current && !accountContainerRef.current.contains(target)) setShowAccount(false);
    };
    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, []);

  useEffect(() => {
    void loadNotifications();
    const query = searchTerm.trim();
    if (!searchOpen || !query) { setSearchResults([]); setIsSearching(false); return; }
    let active = true;
    setIsSearching(true);
    const roles = user?.roles ?? (user?.role ? [user.role] : []);
    const timer = window.setTimeout(() => {
      void searchGlobalWorkspace(query, roles, user?.permissions ?? []).then(results => { if (active) setSearchResults(results); }).finally(() => { if (active) setIsSearching(false); });
    }, 250);
    return () => { active = false; window.clearTimeout(timer); };
  }, [searchOpen, searchTerm, user?.role, user?.permissions, loadNotifications]);

  useEffect(() => {
    if (!user?.id || user.role === "it_admin") return;
    const channel = supabase.channel(`header-notifications-${user.id}`).on("postgres_changes", { event: "*", schema: "public", table: "notifications" }, () => void loadNotifications()).subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [loadNotifications, user?.id, user?.role]);

  if (!user) return null;
  const closeSearch = () => { setSearchOpen(false); setSearchTerm(""); setSearchResults([]); };

  return <header className="sticky top-0 z-30 border-b border-border/80 bg-card/95 px-3 py-2.5 shadow-sm backdrop-blur supports-[backdrop-filter]:bg-card/80 sm:px-5 lg:px-7">
    <div className="flex min-h-11 items-center gap-3">
      <button type="button" onClick={onMenu} className="inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-border bg-background text-muted-foreground hover:bg-muted hover:text-foreground md:hidden" aria-label="Open navigation"><Menu className="h-5 w-5" /></button>
      <div className="hidden min-w-0 flex-1 sm:block"><p className="text-[10px] font-semibold uppercase tracking-[0.14em] text-primary">Harmony Health Hub</p><h2 className="truncate text-sm font-semibold">{pageLabel}</h2></div>
      <div className="ml-auto flex shrink-0 items-center gap-1 sm:gap-2">
        <div ref={searchContainerRef} className="relative">
          <button type="button" onClick={() => { setSearchOpen(v => !v); setShowNotifications(false); setShowAccount(false); }} className={cn("rounded-xl p-2 hover:bg-muted", searchOpen && "bg-muted")} aria-label="Global search" aria-expanded={searchOpen}><Search className="h-5 w-5 text-muted-foreground" /></button>
          {searchOpen && <div className="absolute right-0 z-50 mt-2 w-[min(30rem,calc(100vw-1rem))] overflow-hidden rounded-2xl border border-border bg-card shadow-elevated">
            <form onSubmit={e => e.preventDefault()} className="border-b p-3"><div className="relative"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" /><input autoFocus value={searchTerm} onChange={e => setSearchTerm(e.target.value)} placeholder="Search modules, features, patients, labs, diagnostics, documents or finance…" className="input-medical h-10 w-full rounded-xl pl-9 pr-9" aria-label="Global search input" />{searchTerm && <button type="button" onClick={() => { setSearchTerm(""); setSearchResults([]); }} className="absolute right-2 top-1/2 -translate-y-1/2 rounded-lg p-1 hover:bg-muted" aria-label="Clear search"><X className="h-4 w-4" /></button>}</div></form>
            {searchTerm.trim() && <div className="max-h-[min(28rem,65vh)] overflow-auto p-2">{isSearching ? <p className="p-4 text-center text-sm text-muted-foreground">Searching…</p> : searchResults.length ? searchResults.map(r => <Link key={`${r.kind}:${r.id}`} to={r.href} onClick={closeSearch} className="block rounded-xl p-3 hover:bg-muted/60"><div className="flex items-start gap-3"><span className="mt-0.5 rounded-md bg-primary/10 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-primary">{r.kind}</span><div className="min-w-0"><p className="text-sm font-medium">{r.title}</p><p className="text-xs text-muted-foreground">{r.subtitle}</p></div></div></Link>) : <p className="p-4 text-center text-sm text-muted-foreground">No matching modules, features or records found.</p>}</div>}
          </div>}
        </div>
        <div ref={notificationContainerRef} className="relative">
          <button type="button" onClick={() => { setShowNotifications(v => { const next = !v; if (next) setNotificationAttention(false); return next; }); setShowAccount(false); setSearchOpen(false); }} className={cn("relative rounded-xl p-2 hover:bg-muted", notificationAttention && "notification-bell-attention")} aria-label="Notifications"><Bell className={cn("h-5 w-5", notificationAttention || hasCritical ? "text-critical" : "text-muted-foreground")} />{unread > 0 && <span className="absolute -right-0.5 -top-0.5 flex min-h-[18px] min-w-[18px] items-center justify-center rounded-full bg-critical px-1 text-[10px] font-bold text-critical-foreground">{unread > 9 ? "9+" : unread}</span>}</button>
          {showNotifications && <div className="absolute right-0 z-50 mt-2 w-[min(24rem,calc(100vw-2rem))] overflow-hidden rounded-2xl border border-border bg-card shadow-elevated"><div className="flex items-center justify-between border-b p-4"><h3 className="font-semibold">Notifications</h3><Link to="/notifications" onClick={() => setShowNotifications(false)} className="text-xs text-primary">View all</Link></div><div className="max-h-96 overflow-y-auto">{notifications.length === 0 ? <p className="p-8 text-center text-sm text-muted-foreground">No notifications yet.</p> : notifications.map(n => <div key={n.id} className={cn("flex cursor-pointer gap-3 border-b p-3 last:border-0 hover:bg-muted/50", !n.is_read && "bg-primary/5")} onClick={() => { void db.rpc("mark_notification_read", { _notification_id: n.id }).finally(() => void loadNotifications()); if (n.link) { setShowNotifications(false); navigate(n.link); } }}>{sevIcon(n.severity)}<div className="min-w-0 flex-1"><p className="text-sm font-medium">{n.title}</p><p className="line-clamp-2 text-xs text-muted-foreground">{n.message}</p></div></div>)}</div></div>}
        </div>
        <button type="button" onClick={() => setTheme(theme === "dark" ? "light" : "dark")} className="rounded-xl p-2 hover:bg-muted" aria-label="Toggle theme">{theme === "dark" ? <Sun className="h-5 w-5 text-muted-foreground" /> : <Moon className="h-5 w-5 text-muted-foreground" />}</button>
        <div ref={accountContainerRef} className="relative">
          <button type="button" onClick={() => { setShowAccount(v => !v); setShowNotifications(false); setSearchOpen(false); }} className="rounded-xl p-1.5 hover:bg-muted" aria-label="Account menu"><div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">{(user.firstName?.[0] || "U").toUpperCase()}{(user.lastName?.[0] || "").toUpperCase()}</div></button>
          {showAccount && <div className="absolute right-0 z-50 mt-2 w-64 overflow-hidden rounded-2xl border border-border bg-card shadow-elevated"><div className="border-b p-4"><p className="text-sm font-semibold">{user.firstName} {user.lastName}</p><p className="truncate text-xs text-muted-foreground">{user.email}</p><p className="mt-1 text-xs text-primary">{roleLabels[user.role]}</p></div><div className="p-2"><Link to="/profile" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><UserRound className="h-4 w-4" />My profile & workspace</Link>{(user.role === "admin" || user.role === "it_admin") && <><Link to="/admin/settings" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><Settings className="h-4 w-4" />System settings</Link>{user.role === "admin" && <Link to="/admin/shifts" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><Clock3 className="h-4 w-4" />Staff shifts</Link>}</>}<Link to="/notifications" onClick={() => setShowAccount(false)} className="flex items-center gap-3 rounded-lg px-3 py-2 text-sm hover:bg-muted"><Bell className="h-4 w-4" />Notifications</Link><button type="button" onClick={() => void logout()} className="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm text-critical hover:bg-critical/10"><LogOut className="h-4 w-4" />Sign out</button></div></div>}
        </div>
      </div>
    </div>
  </header>;
}
