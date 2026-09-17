import { useState } from 'react';
import { Outlet, Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import Sidebar from './Sidebar';
import Header from './Header';
import CriticalAlertOverlay from '@/components/CriticalAlertOverlay';
import EncounterWorkflowOverlay from '@/components/EncounterWorkflowOverlay';
export default function MainLayout(){const{isAuthenticated,loading}=useAuth();const[sidebarCollapsed,setSidebarCollapsed]=useState(false);if(loading)return <div className="min-h-screen flex items-center justify-center bg-background"><div className="animate-pulse text-muted-foreground">Loading…</div></div>;if(!isAuthenticated)return <Navigate to="/login" replace/>;return <div className="min-h-screen bg-background"><Sidebar collapsed={sidebarCollapsed} onToggle={()=>setSidebarCollapsed(v=>!v)}/><div className={`min-w-0 pl-20 transition-[padding] duration-300 ${sidebarCollapsed?'md:pl-20':'md:pl-64'}`}><Header/><main className="min-w-0 p-4 sm:p-6 animate-fade-in"><EncounterWorkflowOverlay/><Outlet/></main></div><CriticalAlertOverlay/></div>}
