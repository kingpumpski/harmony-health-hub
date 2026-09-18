import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { Session, User as SupabaseUser } from '@supabase/supabase-js';
import { UserRole } from '@/types';
import { getDefaultPermissions, permissionByHref, type Permission } from '@/lib/permissions';

interface AppUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: UserRole;
  department?: string;
  specialization?: string;
  permissions: Permission[];
}

interface AuthContextType {
  user: AppUser | null;
  session: Session | null;
  isAuthenticated: boolean;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, firstName: string, lastName: string) => Promise<void>;
  logout: () => Promise<void>;
  switchRole: (role: UserRole) => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

async function loadAppUser(supabaseUser: SupabaseUser): Promise<AppUser> {
  const [{ data: profile, error: profileError }, { data: roleRow, error: roleError }] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', supabaseUser.id).maybeSingle(),
    supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', supabaseUser.id)
      .order('created_at', { ascending: true })
      .limit(1)
      .maybeSingle(),
  ]);
  if (profileError) console.warn('Unable to load user profile; continuing with auth identity.', profileError.message);
  if (roleError) console.warn('Unable to load user role; continuing with default role.', roleError.message);
  const resolvedRole = (roleRow?.role as UserRole) ?? 'patient';
  let permissions = getDefaultPermissions(resolvedRole);
  try {
    const { data: permissionRows, error: permissionError } = await supabase.rpc('get_my_permissions' as never);
    if (permissionError) {
      console.warn('Database permission profile unavailable; using role defaults.', permissionError.message);
    } else if (Array.isArray(permissionRows) && permissionRows.length > 0) {
      permissions = permissionRows
        .map((row: unknown) => typeof row === 'string' ? row : (row as { permission_key?: unknown })?.permission_key)
        .filter((value): value is Permission => typeof value === 'string' && (Object.values(permissionByHref) as string[]).includes(value));
    }
  } catch (error) {
    console.warn('Database permission profile unavailable; using role defaults.', error);
  }
  return {
    id: supabaseUser.id,
    email: supabaseUser.email ?? '',
    firstName: profile?.first_name ?? '',
    lastName: profile?.last_name ?? '',
    role: resolvedRole,
    department: profile?.department ?? undefined,
    specialization: profile?.specialization ?? undefined,
    permissions,
  };
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AppUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    const applySession = async (nextSession: Session | null) => {
      if (!mounted) return;
      setSession(nextSession);
      if (!nextSession?.user) { setUser(null); setLoading(false); return; }
      try {
        const appUser = await loadAppUser(nextSession.user);
        if (mounted) setUser(appUser);
      } catch (error) {
        console.error('Auth profile bootstrap failed; continuing with session.', error);
        if (mounted) setUser({ id: nextSession.user.id, email: nextSession.user.email ?? '', firstName: '', lastName: '', role: 'patient', permissions: getDefaultPermissions('patient') });
      } finally {
        if (mounted) setLoading(false);
      }
    };
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => { void applySession(newSession); });
    void supabase.auth.getSession()
      .then(({ data: { session: existing } }) => applySession(existing))
      .catch((error) => {
        console.error('Unable to restore authentication session.', error);
        if (mounted) { setSession(null); setUser(null); setLoading(false); }
      });
    return () => { mounted = false; sub.subscription.unsubscribe(); };
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  }, []);

  const signUp = useCallback(async (email: string, password: string, firstName: string, lastName: string) => {
    const redirectUrl = `${window.location.origin}/dashboard`;
    const { error } = await supabase.auth.signUp({ email, password, options: { emailRedirectTo: redirectUrl, data: { first_name: firstName, last_name: lastName } } });
    if (error) throw error;
  }, []);

  const logout = useCallback(async () => { await supabase.auth.signOut(); setUser(null); setSession(null); }, []);
  const switchRole = useCallback((_role: UserRole) => { /* Legacy compatibility function. Real roles come from the database. */ }, []);

  return <AuthContext.Provider value={{ user, session, isAuthenticated: !!session, loading, login, signUp, logout, switchRole }}>{children}</AuthContext.Provider>;
}

export function useAuth() { const ctx = useContext(AuthContext); if (!ctx) throw new Error('useAuth must be used within AuthProvider'); return ctx; }
