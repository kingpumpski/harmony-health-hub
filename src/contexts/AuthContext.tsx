import React, { createContext, useContext, useEffect, useState, useCallback, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { Session, User as SupabaseUser } from '@supabase/supabase-js';
import { UserRole } from '@/types';
import { getDefaultPermissions, permissionByHref, rolePermissions, type Permission } from '@/lib/permissions';

interface AppUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: UserRole;
  roles: UserRole[];
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
  refreshUser: () => Promise<void>;
  switchRole: (role: UserRole) => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);
const activeRoleStorageKey = (userId: string) => `hms.activeRole:${userId}`;
const knownPermissions = new Set([...Object.values(permissionByHref), ...Object.values(rolePermissions).flat()] as Permission[]);

async function loadAppUser(supabaseUser: SupabaseUser): Promise<AppUser> {
  const [{ data: profile, error: profileError }, { data: roleRows, error: roleError }] = await Promise.all([
    supabase.from('profiles').select('id,first_name,last_name,department,specialization').eq('id', supabaseUser.id).maybeSingle(),
    supabase.from('user_roles').select('role').eq('user_id', supabaseUser.id).order('created_at', { ascending: true }),
  ]);
  const roles = (roleRows ?? []).map((row) => row.role as UserRole).filter(Boolean);
  const resolvedRole = roles[0] ?? 'patient';
  const persistedRole = typeof window !== 'undefined' ? window.sessionStorage.getItem(activeRoleStorageKey(supabaseUser.id)) as UserRole | null : null;
  const activeRole = persistedRole && roles.includes(persistedRole) ? persistedRole : resolvedRole;
  if (profileError) console.warn('[auth] profile bootstrap unavailable:', profileError.message);
  if (roleError) console.warn('[auth] role bootstrap unavailable:', roleError.message);

  let permissions = getDefaultPermissions(resolvedRole);
  try {
    const { data: permissionRows, error: permissionError } = await supabase.rpc('get_my_permissions' as never);
    if (permissionError) {
      console.warn('[auth] permission catalog unavailable; using role defaults:', permissionError.message);
    } else if (Array.isArray(permissionRows)) {
      const resolved = permissionRows
        .map((row: unknown) => typeof row === 'string' ? row : (row as { permission_key?: unknown })?.permission_key)
        .filter((value): value is Permission => typeof value === 'string' && knownPermissions.has(value as Permission));
      if (resolved.length > 0) permissions = resolved;
    }
  } catch (error) {
    console.warn('[auth] permission bootstrap unavailable; using role defaults:', error);
  }

  return {
    id: supabaseUser.id,
    email: supabaseUser.email ?? '',
    firstName: profile?.first_name ?? '',
    lastName: profile?.last_name ?? '',
    role: activeRole,
    roles: roles.length ? roles : ['patient'],
    department: profile?.department ?? undefined,
    specialization: profile?.specialization ?? undefined,
    permissions,
  };
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AppUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const generation = useRef(0);
  const mountedRef = useRef(true);

  const applySession = useCallback(async (nextSession: Session | null, source: string) => {
    const current = ++generation.current;
    if (!mountedRef.current) return;
    if (import.meta.env.DEV) console.debug('[auth] session event:', source, nextSession ? 'authenticated' : 'anonymous');
    setSession(nextSession);

    if (!nextSession?.user) {
      setUser(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    try {
      const appUser = await loadAppUser(nextSession.user);
      if (!mountedRef.current || current !== generation.current) return;
      setUser(appUser);
      if (typeof window !== 'undefined') window.sessionStorage.setItem(activeRoleStorageKey(appUser.id), appUser.role);
      if (import.meta.env.DEV) console.debug('[auth] session ready:', source);
    } catch (error) {
      if (!mountedRef.current || current !== generation.current) return;
      console.error('[auth] profile bootstrap failed; continuing with session.', error);
      setUser({
        id: nextSession.user.id,
        email: nextSession.user.email ?? '',
        firstName: '',
        lastName: '',
        role: 'patient',
        roles: ['patient'],
        permissions: getDefaultPermissions('patient'),
      });
    } finally {
      if (mountedRef.current && current === generation.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    mountedRef.current = true;
    let subscription: { unsubscribe: () => void } | null = null;

    const initialise = async () => {
      const { data, error } = await supabase.auth.getSession();
      if (!mountedRef.current) return;
      if (error) {
        console.error('[auth] session restore failed:', error);
        await applySession(null, 'restore:error');
        return;
      }
      await applySession(data.session, 'restore');
    };

    const { data } = supabase.auth.onAuthStateChange((event, nextSession) => {
      if (import.meta.env.DEV) console.debug('[auth] event:', event);
      void applySession(nextSession, event);
    });
    subscription = data.subscription;
    void initialise();

    return () => {
      mountedRef.current = false;
      subscription?.unsubscribe();
    };
  }, [applySession]);

  const refreshUser = useCallback(async () => {
    const currentSession = session;
    if (!currentSession?.user) return;
    setLoading(true);
    try {
      const appUser = await loadAppUser(currentSession.user);
      if (mountedRef.current) {
        setUser(appUser);
        if (typeof window !== 'undefined') window.sessionStorage.setItem(activeRoleStorageKey(appUser.id), appUser.role);
      }
    } catch (error) {
      console.error('[auth] unable to refresh application user:', error);
    } finally {
      if (mountedRef.current) setLoading(false);
    }
  }, [session]);

  const login = useCallback(async (email: string, password: string) => {
    if (import.meta.env.DEV) console.debug('[auth] signIn:start');
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    // Ensure the persisted session exists before the caller considers authentication complete.
    if (!data.session) {
      const restored = await supabase.auth.getSession();
      if (!restored.data.session) throw new Error('Authentication succeeded but the session could not be restored.');
    }
    if (import.meta.env.DEV) console.debug('[auth] signIn:success');
  }, []);

  const signUp = useCallback(async (email: string, password: string, firstName: string, lastName: string) => {
    const redirectUrl = `${window.location.origin}${import.meta.env.BASE_URL}dashboard`;
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: { emailRedirectTo: redirectUrl, data: { first_name: firstName, last_name: lastName } },
    });
    if (error) throw error;
  }, []);

  const logout = useCallback(async () => {
    if (import.meta.env.DEV) console.debug('[auth] logout:start');
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    setUser(null);
    setSession(null);
    if (import.meta.env.DEV) console.debug('[auth] logout:complete');
  }, []);

  const switchRole = useCallback((nextRole: UserRole) => {
    setUser((current) => {
      if (!current || !current.roles.includes(nextRole)) return current;
      if (typeof window !== 'undefined') window.sessionStorage.setItem(activeRoleStorageKey(current.id), nextRole);
      return { ...current, role: nextRole };
    });
  }, []);

  return (
    <AuthContext.Provider value={{ user, session, isAuthenticated: !!session, loading, login, signUp, logout, refreshUser, switchRole }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
