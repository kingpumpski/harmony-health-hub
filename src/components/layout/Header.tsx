import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { useNavigate, Link } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import {
  Bell,
  Search,
  Moon,
  Sun,
  AlertTriangle,
  AlertCircle,
  Info,
  CheckCircle2,
  Settings,
  LogOut,
  UserRound,
  Clock3,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { UserRole } from "@/types";
import { searchPatients } from "@/lib/healthApi";
import { supabase } from "@/integrations/supabase/client";
const roleLabels: Record<UserRole, string> = {
  admin: "Administrator",
  practitioner: "Dr.",
  nurse: "Nurse",
  midwife: "Midwife",
  specialist_nurse: "Specialist Nurse",
  radiologist: "Radiologist",
  lab_technician: "Lab Technician",
  pharmacist: "Pharmacist",
  accountant: "Accounts Officer",
  front_desk: "Front Desk Officer",
  canteen: "Canteen Staff",
  patient: "Patient",
};
interface NotifRow {
  id: string;
  title: string;
  message: string;
  severity: string;
  category: string | null;
  link: string | null;
  is_read: boolean;
  created_at: string;
}
const sevIcon = (s: string) =>
  s === "critical" ? (
    <AlertTriangle className="w-4 h-4 text-critical animate-pulse" />
  ) : s === "warning" ? (
    <AlertCircle className="w-4 h-4 text-warning" />
  ) : s === "success" ? (
    <CheckCircle2 className="w-4 h-4 text-success" />
  ) : (
    <Info className="w-4 h-4 text-info" />
  );
export default function Header() {
  const { theme, setTheme } = useTheme();
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [searchTerm, setSearchTerm] = useState("");
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [showNotifications, setShowNotifications] = useState(false);
  const [showAccount, setShowAccount] = useState(false);
  const [notifications, setNotifications] = useState<NotifRow[]>([]);
  const unread = 0;
  const hasCritical = false;
  const greeting =
    `Welcome ${roleLabels[user?.role ?? "patient"]} ${user?.lastName || user?.firstName || ""}`.trim();
  useEffect(() => {
    if (!hasCritical) return;
    const beep = new Audio(
      "data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2teleQ4fk9/qvYIwA2Orzdy/dCANgtnv28RMCx/I+fjObiYNvPT34oM7ChLe//jljT4JGf//+NiVRg4a//7/wZ1ODSQG///cpVgXMhD/9t6lYhg7DP7v2ZhnFjER/+fbnW0ZOg7//dWiaR8yDP/z1KBtJTkN+fjWoW8pMg793tSdcSUoEPz436J2IykQ//baoHUlKBD///emeicuE/7326F3IyYS/fnbpnwnKBL///2me",
    );
    beep.volume = 0.3;
    beep.play().catch(() => {});
  }, [hasCritical]);
  useEffect(() => {
    const query = searchTerm.trim();
    if (!query) {
      setSearchResults([]);
      setIsSearching(false);
      return;
    }
    let active = true;
    setIsSearching(true);
    const timer = window.setTimeout(() => {
      void searchPatients(query)
        .then((results) => {
          if (active) setSearchResults(results.slice(0, 8));
        })
        .finally(() => {
          if (active) setIsSearching(false);
        });
    }, 250);
    return () => {
      active = false;
      window.clearTimeout(timer);
    };
  }, [searchTerm]);
  if (!user) return null;
  return (
    <header className="sticky top-0 z-30 min-h-16 bg-card border-b border-border px-4 sm:px-6 py-2 flex items-center justify-between gap-4">
      <div className="flex-1 min-w-0 max-w-xl">
        <div className="text-xs text-muted-foreground mb-0.5 truncate">
          {greeting}
        </div>
        <form
          onSubmit={(e) => e.preventDefault()}
          className="relative"
        >
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
          <input
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder="Search patients by name, code, phone..."
            className="input-medical pl-10 w-full"
          />
          {searchTerm.trim() && (isSearching || searchResults.length > 0) && (
            <div className="absolute left-0 right-0 z-40 mt-2 rounded-2xl border bg-card p-3 shadow-elevated">
              <div className="space-y-2 max-h-72 overflow-auto">
                {searchResults.slice(0, 8).map((r) => (
                  <Link
                    key={r.id}
                    to={`/patients/${r.id}/chat`}
                    onClick={() => {
                      setSearchResults([]);
                      setSearchTerm("");
                    }}
                    className="block rounded-xl border p-3 hover:bg-muted/50"
                  >
                    <p className="font-medium text-sm">{r.fullName}</p>
                    <p className="text-xs text-muted-foreground">
                      {r.patientId} · {r.phone || "no phone"}
                    </p>
                  </Link>
                ))}
              </div>
            </div>
          )}
          {isSearching && (
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground">
              Searching…
            </span>
          )}
        </form>
      </div>
      <div className="flex items-center gap-1 sm:gap-2 shrink-0">
        <span className="hidden xl:inline text-xs text-muted-foreground mr-1">
          {roleLabels[user.role]}
        </span>
        <div className="relative">
          <button
            onClick={() => setShowNotifications((v) => !v)}
            className={cn(
              "relative p-2 rounded-lg hover:bg-muted",
              hasCritical && "animate-pulse",
            )}
            aria-label="Notifications"
          >
            <Bell
              className={cn(
                "w-5 h-5",
                hasCritical ? "text-critical" : "text-muted-foreground",
              )}
            />
            {unread > 0 && (
              <span className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] text-[10px] font-bold rounded-full bg-critical text-critical-foreground flex items-center justify-center px-1">
                {unread > 9 ? "9+" : unread}
              </span>
            )}
          </button>
          {showNotifications && (
            <div className="absolute right-0 mt-2 w-[min(24rem,calc(100vw-2rem))] bg-card rounded-lg shadow-elevated border z-50">
              <div className="p-3 border-b flex justify-between">
                <h3 className="font-semibold">Notifications</h3>
                <Link
                  to="/notifications"
                  onClick={() => setShowNotifications(false)}
                  className="text-xs text-primary"
                >
                  View all
                </Link>
              </div>
              <div className="max-h-96 overflow-y-auto">
                {notifications.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center p-6">
                    No notifications yet.
                  </p>
                ) : (
                  notifications.map((n) => (
                    <div
                      key={n.id}
                      className={cn(
                        "p-3 border-b last:border-0 hover:bg-muted/50 cursor-pointer flex gap-3",
                        !n.is_read && "bg-primary/5",
                      )}
                      onClick={() => {
                        
                        if (n.link) {
                          setShowNotifications(false);
                          navigate(n.link);
                        }
                      }}
                    >
                      {sevIcon(n.severity)}
                      <div className="flex-1 min-w-0">
                        <p className="font-medium text-sm">{n.title}</p>
                        <p className="text-xs text-muted-foreground line-clamp-2">
                          {n.message}
                        </p>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}
        </div>
        <button
          onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
          className="p-2 rounded-lg hover:bg-muted"
          aria-label="Toggle theme"
        >
          {theme === "dark" ? (
            <Sun className="w-5 h-5 text-muted-foreground" />
          ) : (
            <Moon className="w-5 h-5 text-muted-foreground" />
          )}
        </button>
        <div className="relative">
          <button
            onClick={() => setShowAccount((v) => !v)}
            className="p-1.5 rounded-xl hover:bg-muted"
            aria-label="Account menu"
          >
            <div className="w-8 h-8 rounded-full bg-primary/10 text-primary flex items-center justify-center font-semibold text-xs">
              {(user.firstName?.[0] || "U").toUpperCase()}
              {(user.lastName?.[0] || "").toUpperCase()}
            </div>
          </button>
          {showAccount && (
            <div className="absolute right-0 mt-2 w-64 bg-card rounded-2xl border shadow-elevated z-50 overflow-hidden">
              <div className="p-4 border-b">
                <p className="font-semibold text-sm">
                  {user.firstName} {user.lastName}
                </p>
                <p className="text-xs text-muted-foreground truncate">
                  {user.email}
                </p>
                <p className="text-xs text-primary mt-1">
                  {roleLabels[user.role]}
                </p>
              </div>
              <div className="p-2">
                <Link
                  to="/profile"
                  onClick={() => setShowAccount(false)}
                  className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-muted text-sm"
                >
                  <UserRound className="w-4 h-4" />
                  My profile & workspace
                </Link>
                {user.role === "admin" && (
                  <>
                    <Link
                      to="/admin/settings"
                      onClick={() => setShowAccount(false)}
                      className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-muted text-sm"
                    >
                      <Settings className="w-4 h-4" />
                      System settings
                    </Link>
                    <Link
                      to="/admin/shifts"
                      onClick={() => setShowAccount(false)}
                      className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-muted text-sm"
                    >
                      <Clock3 className="w-4 h-4" />
                      Staff shifts
                    </Link>
                  </>
                )}
                <Link
                  to="/notifications"
                  onClick={() => setShowAccount(false)}
                  className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-muted text-sm"
                >
                  <Bell className="w-4 h-4" />
                  Notifications
                </Link>
                <button
                  onClick={() => void logout()}
                  className="w-full flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-critical/10 text-critical text-sm"
                >
                  <LogOut className="w-4 h-4" />
                  Sign out
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
