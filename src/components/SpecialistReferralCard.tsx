import { CalendarClock, Stethoscope, RotateCcw } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';

export default function SpecialistReferralCard() {
  const { user } = useAuth();
  if (!user || !['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'radiologist'].includes(String(user.role))) return null;
  return (
    <div className="card-medical p-3 space-y-2">
      <div className="flex items-center justify-between gap-3">
        <div><p className="text-[11px] text-muted-foreground">Appointment follow-up</p><p className="text-sm font-semibold text-primary mt-1">Clerking-driven queues</p><p className="text-[10px] text-muted-foreground mt-1">Specialist and review instructions extracted from encounters.</p></div>
        <Stethoscope className="w-5 h-5 text-primary" />
      </div>
      <div className="grid grid-cols-2 gap-2">
        <Link to="/specialist-referrals" className="rounded-lg border border-border p-2 text-xs hover:bg-muted/40"><Stethoscope className="w-3.5 h-3.5 mb-1"/><b>Specialists</b><span className="block text-muted-foreground">Book specialist</span></Link>
        <Link to="/review-appointments" className="rounded-lg border border-border p-2 text-xs hover:bg-muted/40"><RotateCcw className="w-3.5 h-3.5 mb-1"/><b>Reviews</b><span className="block text-muted-foreground">Book review</span></Link>
      </div>
      <div className="text-[10px] text-muted-foreground flex items-center gap-1"><CalendarClock className="w-3 h-3"/> Patient contact details and diagnoses are fetched from the canonical record.</div>
    </div>
  );
}