import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import type { Session, User as SupabaseUser } from '@supabase/supabase-js';
import { UserRole } from '@/types';

interface AppUser {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: UserRole;
  department?: string;
  specialization?: string;
}

interface AuthContextType {
  user: AppUser | null;
  session: Session | null;
  isAuthenticated: boolean;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string, firstName: string, lastName: string) => Promise<void>;
  logout: () => Promise<void>;
  switchRole: (role: UserRole) => void; // legacy no-op kept for compatibility
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

async function loadAppUser(supabaseUser: SupabaseUser): Promise<AppUser> {
  const [{ data: profile }, { data: roleRow }] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', supabaseUser.id).maybeSingle(),
    supabase
      .from('user_roles')
      .select('role')
      .eq('user_id', supabaseUser.id)
      .order('created_at', { ascending: true })
      .limit(1)
      .maybeSingle(),
  ]);

  return {
    id: supabaseUser.id,
    email: supabaseUser.email ?? '',
    firstName: profile?.first_name ?? '',
    lastName: profile?.last_name ?? '',
    role: (roleRow?.role as UserRole) ?? 'patient',
    department: profile?.department ?? undefined,
    specialization: profile?.specialization ?? undefined,
  };
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<AppUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Set up listener FIRST
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      if (newSession?.user) {
        // Defer Supabase calls outside the auth callback
        setTimeout(() => {
          loadAppUser(newSession.user).then(setUser);
        }, 0);
      } else {
        setUser(null);
      }
    });

    // Then load existing session
    supabase.auth.getSession().then(({ data: { session: existing } }) => {
      setSession(existing);
      if (existing?.user) {
        loadAppUser(existing.user).then((u) => {
          setUser(u);
          setLoading(false);
        });
      } else {
        setLoading(false);
      }
    });

    return () => sub.subscription.unsubscribe();
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  }, []);

  const signUp = useCallback(async (email: string, password: string, firstName: string, lastName: string) => {
    const redirectUrl = `${window.location.origin}/dashboard`;
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        emailRedirectTo: redirectUrl,
        data: { first_name: firstName, last_name: lastName },
      },
    });
    if (error) throw error;
  }, []);

  const logout = useCallback(async () => {
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
  }, []);

  const switchRole = useCallback(() => {
    // Legacy demo function — no longer changes role. Real roles come from the DB.
  }, []);

  return (
    <AuthContext.Provider
      value={{
        user,
        session,
        isAuthenticated: !!session,
        loading,
        login,
        signUp,
        logout,
        switchRole,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
