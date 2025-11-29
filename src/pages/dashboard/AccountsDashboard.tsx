import { useState } from 'react';
import { CreditCard, FileText, Users, TrendingUp, AlertTriangle, DollarSign, Receipt, Shield } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import AlertBanner from '@/components/ui/AlertBanner';
import { cn } from '@/lib/utils';

const pendingBills = [
  { id: 1, invoiceNo: 'INV-2024-001', patient: 'John Smith', amount: 1250.00, insurance: { provider: 'BlueCross', coverage: 80 }, status: 'pending', type: 'outpatient' },
  { id: 2, invoiceNo: 'INV-2024-002', patient: 'Mary Williams', amount: 4500.00, insurance: null, status: 'pending', type: 'inpatient' },
  { id: 3, invoiceNo: 'INV-2024-003', patient: 'Robert Brown', amount: 320.00, insurance: { provider: 'Aetna', coverage: 70 }, status: 'partial', type: 'outpatient' },
  { id: 4, invoiceNo: 'INV-2024-004', patient: 'Jennifer Wilson', amount: 8900.00, insurance: { provider: 'UnitedHealth', coverage: 90 }, status: 'pending', type: 'inpatient' },
];

const recentPayments = [
  { id: 1, invoiceNo: 'INV-2024-000', patient: 'Alice Thompson', amount: 450.00, method: 'Card', time: '10 min ago' },
  { id: 2, invoiceNo: 'INV-2023-999', patient: 'George Martinez', amount: 1200.00, method: 'Insurance', time: '30 min ago' },
  { id: 3, invoiceNo: 'INV-2023-998', patient: 'Susan Anderson', amount: 85.00, method: 'Cash', time: '1 hour ago' },
];

const dailySummary = {
  outpatient: { count: 45, revenue: 12500 },
  inpatient: { count: 12, revenue: 48000 },
  pharmacy: { count: 86, revenue: 4200 },
  lab: { count: 62, revenue: 3100 },
};

export default function AccountsDashboard() {
  const [showInsuranceAlert, setShowInsuranceAlert] = useState(true);

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Billing & Accounts</h1>
          <p className="text-muted-foreground">Financial Management Dashboard</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary">
            <FileText className="w-4 h-4" />
            Reports
          </button>
          <button className="btn-primary">
            <CreditCard className="w-4 h-4" />
            New Invoice
          </button>
        </div>
      </div>

      {/* Insurance Alert */}
      {showInsuranceAlert && (
        <AlertBanner
          type="info"
          title="Insurance Verification Required"
          message="3 patients have pending insurance verification. Please verify before billing."
          onDismiss={() => setShowInsuranceAlert(false)}
        />
      )}

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Today's Revenue"
          value="$67,800"
          change="+12% from yesterday"
          changeType="positive"
          icon={DollarSign}
          iconColor="text-success"
        />
        <StatCard
          title="Pending Bills"
          value={32}
          change="$124,500 total"
          changeType="neutral"
          icon={Receipt}
          iconColor="text-warning"
        />
        <StatCard
          title="Outstanding"
          value="$45,200"
          change="8 overdue"
          changeType="negative"
          icon={AlertTriangle}
          iconColor="text-critical"
        />
        <StatCard
          title="Insurance Claims"
          value={18}
          change="$89,000 pending"
          changeType="neutral"
          icon={Shield}
          iconColor="text-info"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Pending Bills */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Pending Bills</h2>
            <div className="flex gap-2">
              {['all', 'outpatient', 'inpatient'].map((filter) => (
                <button
                  key={filter}
                  className="px-3 py-1.5 rounded-lg text-xs font-medium bg-muted text-muted-foreground hover:bg-muted/80 capitalize"
                >
                  {filter}
                </button>
              ))}
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="table-medical">
              <thead>
                <tr>
                  <th>Invoice</th>
                  <th>Patient</th>
                  <th>Amount</th>
                  <th>Insurance</th>
                  <th>Type</th>
                  <th>Status</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {pendingBills.map((bill) => (
                  <tr key={bill.id}>
                    <td className="font-mono text-sm">{bill.invoiceNo}</td>
                    <td className="font-medium">{bill.patient}</td>
                    <td className="font-semibold">${bill.amount.toFixed(2)}</td>
                    <td>
                      {bill.insurance ? (
                        <div className="flex items-center gap-2">
                          <Shield className="w-4 h-4 text-success" />
                          <div>
                            <p className="text-sm font-medium">{bill.insurance.provider}</p>
                            <p className="text-xs text-muted-foreground">{bill.insurance.coverage}% coverage</p>
                          </div>
                        </div>
                      ) : (
                        <span className="text-muted-foreground text-sm">Self-pay</span>
                      )}
                    </td>
                    <td>
                      <span className={cn(
                        'badge-status capitalize',
                        bill.type === 'inpatient' ? 'badge-info' : 'bg-muted text-muted-foreground'
                      )}>
                        {bill.type}
                      </span>
                    </td>
                    <td>
                      <span className={cn(
                        'badge-status',
                        bill.status === 'pending' && 'badge-warning',
                        bill.status === 'partial' && 'badge-info'
                      )}>
                        {bill.status}
                      </span>
                    </td>
                    <td>
                      <button className="btn-primary text-xs py-1 px-2">Process</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary">View All Bills →</button>
          </div>
        </div>

        {/* Recent Payments */}
        <div className="card-medical">
          <div className="p-5 border-b border-border">
            <h2 className="font-semibold">Recent Payments</h2>
          </div>
          <div className="divide-y divide-border">
            {recentPayments.map((payment) => (
              <div key={payment.id} className="p-4 hover:bg-muted/30 transition-colors">
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-mono text-xs text-muted-foreground">{payment.invoiceNo}</p>
                    <p className="font-medium mt-1">{payment.patient}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">{payment.method}</p>
                  </div>
                  <div className="text-right">
                    <p className="font-semibold text-success">${payment.amount.toFixed(2)}</p>
                    <p className="text-xs text-muted-foreground mt-1">{payment.time}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary w-full">View All Payments →</button>
          </div>
        </div>
      </div>

      {/* Daily Summary */}
      <div className="card-medical p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold">Today's Revenue Summary</h2>
          <button className="btn-ghost text-sm">Download Report</button>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {Object.entries(dailySummary).map(([key, value]) => (
            <div key={key} className="p-4 bg-muted/30 rounded-lg">
              <p className="text-sm text-muted-foreground capitalize">{key}</p>
              <p className="text-2xl font-bold mt-1">${(value.revenue / 1000).toFixed(1)}K</p>
              <p className="text-xs text-muted-foreground mt-1">{value.count} transactions</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
