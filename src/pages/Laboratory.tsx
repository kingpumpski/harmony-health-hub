import { useMemo, useState } from 'react';
import { FlaskConical, ClipboardList, Bell, Clock, CheckCircle, Upload, ServerCog, Activity, MessageSquare } from 'lucide-react';

const sampleOrders = [
  { id: 'L-001', patient: 'Ama K.', test: 'CBC', status: 'pending' },
  { id: 'L-002', patient: 'Samuel N.', test: 'Malaria Rapid', status: 'in-progress' },
  { id: 'L-003', patient: 'Sarah B.', test: 'Lipid Profile', status: 'completed' },
];

export default function Laboratory() {
  const [orders, setOrders] = useState(sampleOrders);
  const [activeResult, setActiveResult] = useState('L-003');
  const [showChat, setShowChat] = useState(true);
  const activeOrder = useMemo(() => orders.find((order) => order.id === activeResult), [orders, activeResult]);

  const handleCollect = (id: string) => {
    setOrders((prev) => prev.map((order) => (order.id === id ? { ...order, status: 'in-progress' } : order)));
  };

  const handleUpload = (id: string) => {
    setOrders((prev) => prev.map((order) => (order.id === id ? { ...order, status: 'completed' } : order)));
    setActiveResult(id);
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Laboratory Information System</h1>
          <p className="text-muted-foreground">Order tests, track samples, and notify clinicians.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <FlaskConical className="w-4 h-4" /> New Lab Order
        </button>
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(320px,_360px)_1fr]">
        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Lab Orders</h2>
              <p className="text-sm text-muted-foreground">Track order status and sample flow.</p>
            </div>
            <ClipboardList className="w-5 h-5 text-primary" />
          </div>
          <div className="space-y-3">
            {orders.map((order) => (
              <div key={order.id} className="rounded-2xl border border-border p-4 flex items-center justify-between gap-3">
                <div>
                  <p className="font-medium">{order.test}</p>
                  <p className="text-xs text-muted-foreground">{order.patient}</p>
                </div>
                <div className="flex items-center gap-2">
                  <span className={`badge-status ${order.status === 'completed' ? 'badge-success' : order.status === 'in-progress' ? 'badge-warning' : 'badge-info'}`}>
                    {order.status.replace('-', ' ')}
                  </span>
                  {order.status !== 'completed' && (
                    <button onClick={() => handleCollect(order.id)} className="btn-ghost text-xs">Collect</button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="card-medical p-6 relative">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Result Panel</h2>
              <p className="text-sm text-muted-foreground">Upload and validate completed laboratory results.</p>
            </div>
            <Bell className="w-5 h-5 text-warning" />
          </div>

          {activeOrder ? (
            <div className="space-y-4">
              <div className="rounded-2xl border border-border p-4">
                <p className="text-sm text-muted-foreground">Selected Order</p>
                <p className="mt-2 font-medium">{activeOrder.test} · {activeOrder.patient}</p>
              </div>
              <div className="grid gap-4 md:grid-cols-2">
                <button onClick={() => handleUpload(activeOrder.id)} className="btn-primary">Upload Result</button>
                <button className="btn-secondary">Validate Result</button>
              </div>
              <div className="rounded-2xl border border-border p-4 bg-background/60">
                <p className="font-medium">Recent Result Notes</p>
                <p className="text-sm text-muted-foreground mt-2">Sample registered and pending approval. Notify requesting clinician on completion.</p>
              </div>
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">Select an order to view details.</p>
          )}

          {showChat && (
            <div className="absolute right-6 top-24 w-72 rounded-3xl border border-border bg-card p-4 shadow-elevated">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <h3 className="font-semibold">Lab Chat Panel</h3>
                  <p className="text-xs text-muted-foreground">Live clinician notifications</p>
                </div>
                <button onClick={() => setShowChat(false)} className="text-muted-foreground text-xs">Close</button>
              </div>
              <div className="space-y-3">
                <div className="rounded-2xl border border-border p-3 bg-background/80">
                  <p className="text-xs text-muted-foreground">Lab</p>
                  <p className="text-sm">Blood work ready for Dr. Sarah. Please review sample quality.</p>
                </div>
                <div className="rounded-2xl border border-border p-3 bg-background/80">
                  <p className="text-xs text-muted-foreground">Clinician</p>
                  <p className="text-sm">Send urgent malaria result by SMS.</p>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="card-medical p-6">
          <div className="flex items-center gap-3 mb-4">
            <Clock className="w-5 h-5 text-success" />
            <h2 className="text-lg font-semibold">Turnaround Time</h2>
          </div>
          <p className="text-sm text-muted-foreground">Average lab processing for urgent diagnostics.</p>
          <div className="mt-4 rounded-2xl border border-border p-4 text-center">
            <p className="text-3xl font-semibold">2.4h</p>
            <p className="text-sm text-muted-foreground">Average completion time</p>
          </div>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center gap-3 mb-4">
            <ServerCog className="w-5 h-5 text-primary" />
            <h2 className="text-lg font-semibold">Automation</h2>
          </div>
          <p className="text-sm text-muted-foreground">Automatic sample status updates and clinician alerts.</p>
          <div className="mt-4 rounded-2xl border border-border p-4 bg-success/10 text-success">
            <p className="font-medium">Complimentary result validation task created.</p>
          </div>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center gap-3 mb-4">
            <MessageSquare className="w-5 h-5 text-warning" />
            <h2 className="text-lg font-semibold">Notifications</h2>
          </div>
          <p className="text-sm text-muted-foreground">Doctors receive lab-ready alerts immediately.</p>
          <div className="mt-4 rounded-2xl border border-border p-4">
            <p className="font-medium">2 critical results pending review.</p>
          </div>
        </div>
      </div>
    </div>
  );
}
