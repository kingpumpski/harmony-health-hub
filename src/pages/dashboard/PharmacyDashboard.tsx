import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Pill, Package, AlertTriangle, CheckCircle, Search, Clock, TrendingDown, ShoppingCart } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import AlertBanner from '@/components/ui/AlertBanner';
import { cn } from '@/lib/utils';

const pendingPrescriptions = [
  { id: 1, rxId: 'RX-2024-001', patient: 'John Smith', doctor: 'Dr. Sarah Johnson', items: 3, priority: 'urgent', time: '5 min ago', status: 'pending' },
  { id: 2, rxId: 'RX-2024-002', patient: 'Mary Williams', doctor: 'Dr. Michael Chen', items: 2, priority: 'normal', time: '15 min ago', status: 'pending' },
  { id: 3, rxId: 'RX-2024-003', patient: 'Robert Brown', doctor: 'Dr. Emily Davis', items: 5, priority: 'normal', time: '20 min ago', status: 'processing' },
  { id: 4, rxId: 'RX-2024-004', patient: 'Jennifer Wilson', doctor: 'Dr. Sarah Johnson', items: 1, priority: 'stat', time: '2 min ago', status: 'pending' },
];

const lowStockItems = [
  { id: 1, name: 'Paracetamol 500mg', stock: 45, reorderLevel: 100, daysLeft: 3 },
  { id: 2, name: 'Amoxicillin 500mg', stock: 28, reorderLevel: 50, daysLeft: 2 },
  { id: 3, name: 'Metformin 850mg', stock: 62, reorderLevel: 80, daysLeft: 5 },
  { id: 4, name: 'Omeprazole 20mg', stock: 15, reorderLevel: 40, daysLeft: 1 },
];

const recentDispensed = [
  { id: 1, rxId: 'RX-2024-000', patient: 'Alice Thompson', items: 2, total: 45.00, time: '10 min ago' },
  { id: 2, rxId: 'RX-2023-999', patient: 'George Martinez', items: 4, total: 128.50, time: '25 min ago' },
  { id: 3, rxId: 'RX-2023-998', patient: 'Susan Anderson', items: 1, total: 22.00, time: '40 min ago' },
];

export default function PharmacyDashboard() {
  const navigate = useNavigate();
  const [showLowStockAlert, setShowLowStockAlert] = useState(true);

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Pharmacy Dashboard</h1>
          <p className="text-muted-foreground">Dispensing & Inventory Management</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary" onClick={() => navigate('/inventory')}>
            <Package className="w-4 h-4" />
            Inventory
          </button>
          <button className="btn-primary" onClick={() => navigate('/dispensing')}>
            <Pill className="w-4 h-4" />
            Dispense
          </button>
        </div>
      </div>

      {/* Low Stock Alert */}
      {showLowStockAlert && (
        <AlertBanner
          type="warning"
          title="Low Stock Alert - 4 Items Below Reorder Level"
          message="Omeprazole 20mg critically low (1 day supply). Consider placing urgent order."
          onDismiss={() => setShowLowStockAlert(false)}
        />
      )}

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Pending Prescriptions"
          value={24}
          change="2 stat priority"
          changeType="negative"
          icon={Pill}
          iconColor="text-warning"
        />
        <StatCard
          title="Dispensed Today"
          value={86}
          change="+15% from yesterday"
          changeType="positive"
          icon={CheckCircle}
          iconColor="text-success"
        />
        <StatCard
          title="Low Stock Items"
          value={12}
          change="4 critical"
          changeType="negative"
          icon={TrendingDown}
          iconColor="text-critical"
        />
        <StatCard
          title="Total Inventory"
          value="2,847"
          change="Items in stock"
          changeType="neutral"
          icon={Package}
          iconColor="text-info"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Prescription Queue */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Prescription Queue</h2>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <input
                type="text"
                placeholder="Search prescriptions..."
                className="input-medical pl-9 py-1.5 text-sm w-48"
              />
            </div>
          </div>
          <div className="divide-y divide-border">
            {pendingPrescriptions.map((rx) => (
              <div
                key={rx.id}
                className={cn(
                  'p-4 transition-colors hover:bg-muted/30',
                  rx.priority === 'stat' && 'bg-critical/5 border-l-2 border-l-critical'
                )}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className="text-center">
                      <p className="font-mono text-sm text-primary">{rx.rxId}</p>
                      <span className={cn(
                        'badge-status text-[10px] mt-1',
                        rx.priority === 'stat' && 'badge-critical pulse-critical',
                        rx.priority === 'urgent' && 'badge-warning',
                        rx.priority === 'normal' && 'badge-info'
                      )}>
                        {rx.priority.toUpperCase()}
                      </span>
                    </div>
                    <div>
                      <p className="font-medium">{rx.patient}</p>
                      <p className="text-sm text-muted-foreground">{rx.doctor}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-4">
                    <div className="text-right">
                      <p className="text-sm font-medium">{rx.items} items</p>
                      <p className="text-xs text-muted-foreground">{rx.time}</p>
                    </div>
                    <span className={cn(
                      'badge-status',
                      rx.status === 'pending' && 'bg-muted text-muted-foreground',
                      rx.status === 'processing' && 'badge-info'
                    )}>
                      {rx.status}
                    </span>
                    <button className="btn-primary text-sm py-1.5" onClick={() => navigate('/pharmacy')}>
                      {rx.status === 'pending' ? 'Process' : 'Continue'}
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary" onClick={() => navigate('/pharmacy')}>View All Prescriptions →</button>
          </div>
        </div>

        {/* Low Stock Items */}
        <div className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Low Stock Alerts</h2>
            <span className="badge-critical">{lowStockItems.length} items</span>
          </div>
          <div className="divide-y divide-border">
            {lowStockItems.map((item) => (
              <div key={item.id} className="p-4 hover:bg-muted/30 transition-colors cursor-pointer" onClick={() => navigate('/inventory')}>
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-medium text-sm">{item.name}</p>
                    <p className="text-xs text-muted-foreground mt-1">
                      Current: {item.stock} / Reorder: {item.reorderLevel}
                    </p>
                  </div>
                  <span className={cn(
                    'badge-status',
                    item.daysLeft <= 1 && 'badge-critical pulse-critical',
                    item.daysLeft <= 3 && item.daysLeft > 1 && 'badge-warning',
                    item.daysLeft > 3 && 'badge-info'
                  )}>
                    {item.daysLeft} days
                  </span>
                </div>
                <div className="mt-3 h-2 bg-muted rounded-full overflow-hidden">
                  <div
                    className={cn(
                      'h-full rounded-full transition-all',
                      (item.stock / item.reorderLevel) < 0.3 ? 'bg-critical' :
                      (item.stock / item.reorderLevel) < 0.6 ? 'bg-warning' : 'bg-success'
                    )}
                    style={{ width: `${Math.min((item.stock / item.reorderLevel) * 100, 100)}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-secondary w-full" onClick={() => navigate('/inventory')}>
              <ShoppingCart className="w-4 h-4" />
              Create Reorder
            </button>
          </div>
        </div>
      </div>

      {/* Recently Dispensed */}
      <div className="card-medical p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold">Recently Dispensed</h2>
          <button className="btn-ghost text-sm" onClick={() => navigate('/pharmacy')}>View All</button>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {recentDispensed.map((item) => (
            <div key={item.id} className="p-4 bg-muted/30 rounded-lg cursor-pointer hover:bg-muted/50 transition-colors" onClick={() => navigate('/pharmacy')}>
              <div className="flex items-center justify-between mb-2">
                <span className="font-mono text-sm text-primary">{item.rxId}</span>
                <span className="text-xs text-muted-foreground">{item.time}</span>
              </div>
              <p className="font-medium">{item.patient}</p>
              <div className="flex items-center justify-between mt-2 text-sm">
                <span className="text-muted-foreground">{item.items} items</span>
                <span className="font-semibold">${item.total.toFixed(2)}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
