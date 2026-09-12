import { useEffect,useState } from 'react';
import { Bell,LogOut,Shield,UserRound } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

export default function Profile(){
 const{user,logout}=useAuth();
 const[department,setDepartment]=useState('');
 const[specialization,setSpecialization]=useState('');
 const[phone,setPhone]=useState('');
 const[loading,setLoading]=useState(true);
 useEffect(()=>{if(!user)return;void(async()=>{const{data}=await supabase.from('profiles').select('department,specialization,phone').eq('id',user.id).maybeSingle();setDepartment(data?.department??'');setSpecialization(data?.specialization??'');setPhone(data?.phone??'');setLoading(false)})()},[user]);
 if(!user)return null;
 const save=async()=>{const{error}=await supabase.from('profiles').update({phone:phone||null}).eq('id',user.id);if(error)toast.error(error.message);else toast.success('Profile preferences saved.');};
 return <div className="space-y-6 animate-fade-in max-w-3xl"><header><h1 className="text-2xl font-heading font-bold flex items-center gap-2"><UserRound className="w-6 h-6 text-primary"/>My Profile & Workspace</h1><p className="text-muted-foreground">Your account identity, operational assignment and personal workspace links.</p></header><section className="card-medical rounded-3xl p-6"><div className="flex items-center gap-4"><div className="w-14 h-14 rounded-2xl bg-primary/10 text-primary flex items-center justify-center font-bold">{(user.firstName?.[0]??'U').toUpperCase()}{(user.lastName?.[0]??'').toUpperCase()}</div><div><h2 className="text-lg font-semibold">{user.firstName} {user.lastName}</h2><p className="text-sm text-muted-foreground">{user.email}</p><p className="text-xs text-primary capitalize mt-1">{user.role.replaceAll('_',' ')}</p></div></div><div className="grid md:grid-cols-2 gap-4 mt-6"><div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Department</p><p className="font-medium mt-1">{loading?'Loading…':department||'Not assigned'}</p></div><div className="rounded-xl border p-4"><p className="text-xs text-muted-foreground">Specialization</p><p className="font-medium mt-1">{loading?'Loading…':specialization||'Not assigned'}</p></div></div><label className="block text-sm mt-5 space-y-1"><span>Contact phone</span><input className="input-medical w-full" value={phone} onChange={e=>setPhone(e.target.value)} placeholder="Phone number"/></label><button className="btn-primary mt-4" onClick={()=>void save()}>Save profile</button></section><section className="grid sm:grid-cols-2 gap-4"><Link to="/notifications" className="card-medical p-5 hover:border-primary transition"><Bell className="w-5 h-5 text-primary"/><h2 className="font-semibold mt-3">Notifications</h2><p className="text-sm text-muted-foreground mt-1">Review clinical, billing and operational alerts.</p></Link>{user.role==='admin'&&<Link to="/admin/settings" className="card-medical p-5 hover:border-primary transition"><Shield className="w-5 h-5 text-primary"/><h2 className="font-semibold mt-3">System Settings</h2><p className="text-sm text-muted-foreground mt-1">Manage facility configuration, tariffs, laboratory catalogue and staff operations.</p></Link>}</section><button onClick={()=>void logout()} className="btn-secondary inline-flex items-center gap-2 text-critical"><LogOut className="w-4 h-4"/>Sign out</button></div>;
}
