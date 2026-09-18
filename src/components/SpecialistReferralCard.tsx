import { CalendarClock, Stethoscope } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';

export default function SpecialistReferralCard() {
  const { user } = useAuth();
  if (!user || !['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'radiologist'].includes(String(user.role))) return null;
  return (
    <Link to="/specialist-referrals" className="card-medical p-3 block transition-all hover:-translate-y-0.5 hover:shadow-elevated">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-[11px] text-muted-foreground">Specialist referrals</p>
          <p className="text-sm font-semibold text-primary mt-1">Open referral queue</p>
          <p className="text-[10px] text-muted-foreground mt-1">Scheduled referrals needing attention</p>
        </div>
        <div className="flex flex-col items-end gap-1"><Stethoscope className="w-5 h-5 text-primary" /><CalendarClock className="w-3.5 h-3.5 text-success" /></div>
      </div>
    </Link>
  );
}
