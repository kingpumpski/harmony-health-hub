import React, { createContext, useContext, useState, useCallback } from 'react';
import { User, UserRole } from '@/types';

interface AuthContextType {
  user: User | null;
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
  switchRole: (role: UserRole) => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

// Demo users for different roles
const demoUsers: Record<UserRole, User> = {
  admin: {
    id: '1',
    email: 'admin@medicarepro.com',
    firstName: 'Admin',
    lastName: 'User',
    role: 'admin',
    department: 'Administration',
  },
  practitioner: {
    id: '2',
    email: 'doctor@medicarepro.com',
    firstName: 'Dr. Sarah',
    lastName: 'Johnson',
    role: 'practitioner',
    department: 'Internal Medicine',
    specialization: 'General Practitioner',
  },
  nurse: {
    id: '3',
    email: 'nurse@medicarepro.com',
    firstName: 'Emily',
    lastName: 'Williams',
    role: 'nurse',
    department: 'Nursing',
  },
  midwife: {
    id: '4',
    email: 'midwife@medicarepro.com',
    firstName: 'Grace',
    lastName: 'Thompson',
    role: 'midwife',
    department: 'Maternity',
  },
  lab_technician: {
    id: '5',
    email: 'lab@medicarepro.com',
    firstName: 'Michael',
    lastName: 'Chen',
    role: 'lab_technician',
    department: 'Laboratory',
  },
  pharmacist: {
    id: '6',
    email: 'pharmacy@medicarepro.com',
    firstName: 'David',
    lastName: 'Brown',
    role: 'pharmacist',
    department: 'Pharmacy',
  },
  accountant: {
    id: '7',
    email: 'accounts@medicarepro.com',
    firstName: 'Lisa',
    lastName: 'Anderson',
    role: 'accountant',
    department: 'Finance',
  },
  front_desk: {
    id: '8',
    email: 'reception@medicarepro.com',
    firstName: 'Jennifer',
    lastName: 'Davis',
    role: 'front_desk',
    department: 'Reception',
  },
  canteen: {
    id: '9',
    email: 'canteen@medicarepro.com',
    firstName: 'Robert',
    lastName: 'Wilson',
    role: 'canteen',
    department: 'Food Services',
  },
  patient: {
    id: '10',
    email: 'patient@email.com',
    firstName: 'John',
    lastName: 'Doe',
    role: 'patient',
  },
};

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);

  const login = useCallback(async (email: string, password: string) => {
    // Demo login - in production, this would validate against Supabase
    const role = Object.keys(demoUsers).find(
      (key) => demoUsers[key as UserRole].email === email
    ) as UserRole | undefined;

    if (role) {
      setUser(demoUsers[role]);
    } else {
      // Default to front_desk for demo
      setUser(demoUsers.front_desk);
    }
  }, []);

  const logout = useCallback(() => {
    setUser(null);
  }, []);

  const switchRole = useCallback((role: UserRole) => {
    setUser(demoUsers[role]);
  }, []);

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated: !!user,
        login,
        logout,
        switchRole,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
