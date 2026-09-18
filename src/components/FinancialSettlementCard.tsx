import { CircleDollarSign, FileCheck2, RefreshCw } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';

export default function FinancialSettlementCard() {
  const { user } = useAuth();
  if (!user || !['admin', 'accountant'].includes(String(user.role))) return null;

  return (
    <section aria-label="Financial settlement" className="card-medical p-5 space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h2 className="font-semibold flex items-center gap-2"><CircleDollarSign className="w-4 h-4 text-primary" />Financial settlement</h2>
          <p className="text-xs text-muted-foreground">Open the live insurance settlement worklist.</p>
        </div>
        <FileCheck2 className="w-5 h-5 text-success" />
      </div>
      <Link to="/insurance-claims" className="block rounded-xl p-4 bg-primary/5 transition-all duration-300 hover:-translate-y-1 hover:shadow-elevated">
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="text-xs text-muted-foreground">Insurance settlement worklist</p>
            <p className="text-sm font-medium mt-1">Review claims, approvals, exceptions and payments</p>
          </div>
          <RefreshCw className="w-5 h-5 text-primary" />
        </div>
      </Link>
    </section>
  );
}
