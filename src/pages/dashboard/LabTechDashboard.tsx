import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { FlaskConical, Clock, CheckCircle, AlertTriangle, FileText, Search, Filter, Send } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import { cn } from '@/lib/utils';

const pendingTests = [
  { id: 1, labId: 'LAB-2024-001', patient: 'John Smith', test: 'Complete Blood Count', priority: 'stat', requestedBy: 'Dr. Sarah Johnson', time: '10 min ago', status: 'pending' },
  { id: 2, labId: 'LAB-2024-002', patient: 'Mary Williams', test: 'Liver Function Panel', priority: 'urgent', requestedBy: 'Dr. Michael Chen', time: '25 min ago', status: 'in-progress' },
  { id: 3, labId: 'LAB-2024-003', patient: 'Robert Brown', test: 'HbA1c', priority: 'routine', requestedBy: 'Dr. Emily Davis', time: '1 hour ago', status: 'pending' },
  { id: 4, labId: 'LAB-2024-004', patient: 'Jennifer Wilson', test: 'Thyroid Panel', priority: 'routine', requestedBy: 'Dr. Sarah Johnson', time: '2 hours ago', status: 'pending' },
  { id: 5, labId: 'LAB-2024-005', patient: 'David Miller', test: 'Urinalysis', priority: 'urgent', requestedBy: 'Dr. James Taylor', time: '30 min ago', status: 'completed' },
];

const completedToday = [
  { id: 1, labId: 'LAB-2024-000', patient: 'Alice Thompson', test: 'CBC', result: 'Normal', completedAt: '9:30 AM', approvedBy: 'Dr. Chen' },
  { id: 2, labId: 'LAB-2023-999', patient: 'George Martinez', test: 'Lipid Panel', result: 'Abnormal', completedAt: '9:15 AM', approvedBy: 'Pending' },
  { id: 3, labId: 'LAB-2023-998', patient: 'Susan Anderson', test: 'Glucose', result: 'Normal', completedAt: '8:45 AM', approvedBy: 'Dr. Johnson' },
];

export default function LabTechDashboard() {
  const navigate = useNavigate();
  const [selectedStatus, setSelectedStatus] = useState('all');
  const [selectedTest, setSelectedTest] = useState<string | null>(null);

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Laboratory Dashboard</h1>
          <p className="text-muted-foreground">Clinical Laboratory • Hematology & Biochemistry</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary" onClick={() => navigate('/treatment-templates')}>
            <FileText className="w-4 h-4" />
            Templates
          </button>
          <button className="btn-primary" onClick={() => navigate('/laboratory')}>
            <FlaskConical className="w-4 h-4" />
            New Result Entry
          </button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Pending Tests"
          value={18}
          change="3 stat priority"
          changeType="negative"
          icon={FlaskConical}
          iconColor="text-warning"
        />
        <StatCard
          title="In Progress"
          value={5}
          change="Avg. 25 min processing"
          changeType="neutral"
          icon={Clock}
          iconColor="text-info"
        />
        <StatCard
          title="Completed Today"
          value={42}
          change="+12 from yesterday"
          changeType="positive"
          icon={CheckCircle}
          iconColor="text-success"
        />
        <StatCard
          title="Pending Approval"
          value={8}
          change="2 abnormal results"
          changeType="negative"
          icon={AlertTriangle}
          iconColor="text-critical"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Test Queue */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Test Queue</h2>
            <div className="flex items-center gap-3">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <input
                  type="text"
                  placeholder="Search by Lab ID or patient..."
                  className="input-medical pl-9 py-1.5 text-sm w-56"
                />
              </div>
              <div className="flex gap-1">
                {['all', 'stat', 'urgent', 'routine'].map((filter) => (
                  <button
                    key={filter}
                    onClick={() => setSelectedStatus(filter)}
                    className={cn(
                      'px-3 py-1.5 rounded-lg text-xs font-medium transition-colors capitalize',
                      selectedStatus === filter
                        ? 'bg-primary text-primary-foreground'
                        : 'bg-muted text-muted-foreground hover:bg-muted/80'
                    )}
                  >
                    {filter}
                  </button>
                ))}
              </div>
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="table-medical">
              <thead>
                <tr>
                  <th>Lab ID</th>
                  <th>Patient</th>
                  <th>Test</th>
                  <th>Priority</th>
                  <th>Requested By</th>
                  <th>Status</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {pendingTests
                  .filter(t => selectedStatus === 'all' || t.priority === selectedStatus)
                  .map((test) => (
                  <tr
                    key={test.id}
                    className={cn(
                      'cursor-pointer',
                      selectedTest === test.labId && 'bg-primary/5',
                      test.priority === 'stat' && 'bg-critical/5'
                    )}
                    onClick={() => setSelectedTest(test.labId)}
                  >
                    <td className="font-mono text-sm">{test.labId}</td>
                    <td className="font-medium">{test.patient}</td>
                    <td>{test.test}</td>
                    <td>
                      <span className={cn(
                        'badge-status',
                        test.priority === 'stat' && 'badge-critical pulse-critical',
                        test.priority === 'urgent' && 'badge-warning',
                        test.priority === 'routine' && 'badge-info'
                      )}>
                        {test.priority.toUpperCase()}
                      </span>
                    </td>
                    <td className="text-muted-foreground">{test.requestedBy}</td>
                    <td>
                      <span className={cn(
                        'badge-status',
                        test.status === 'pending' && 'bg-muted text-muted-foreground',
                        test.status === 'in-progress' && 'badge-info',
                        test.status === 'completed' && 'badge-success'
                      )}>
                        {test.status}
                      </span>
                    </td>
                    <td>
                      <button className="btn-primary text-xs py-1 px-2" onClick={() => navigate('/laboratory')}>
                        {test.status === 'pending' ? 'Start' : test.status === 'completed' ? 'View' : 'Continue'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Completed Tests */}
        <div className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Recently Completed</h2>
            <span className="badge-success">{completedToday.length} today</span>
          </div>
          <div className="divide-y divide-border">
            {completedToday.map((test) => (
              <div key={test.id} className="p-4 hover:bg-muted/30 transition-colors cursor-pointer" onClick={() => navigate('/laboratory')}>
                <div className="flex items-start justify-between">
                  <div>
                    <p className="font-mono text-xs text-muted-foreground">{test.labId}</p>
                    <p className="font-medium mt-1">{test.patient}</p>
                    <p className="text-sm text-muted-foreground">{test.test}</p>
                  </div>
                  <span className={cn(
                    'badge-status',
                    test.result === 'Normal' ? 'badge-success' : 'badge-warning'
                  )}>
                    {test.result}
                  </span>
                </div>
                <div className="flex items-center justify-between mt-3 text-xs">
                  <span className="text-muted-foreground">{test.completedAt}</span>
                  <span className={cn(
                    test.approvedBy === 'Pending' ? 'text-warning' : 'text-success'
                  )}>
                    {test.approvedBy === 'Pending' ? 'Awaiting Approval' : `Approved: ${test.approvedBy}`}
                  </span>
                </div>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-ghost text-sm text-primary w-full" onClick={() => navigate('/laboratory')}>View All Completed →</button>
          </div>
        </div>
      </div>

      {/* Quick Result Templates */}
      <div className="card-medical p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold">Quick Result Templates</h2>
          <button className="btn-ghost text-sm" onClick={() => navigate('/treatment-templates')}>Manage Templates</button>
        </div>
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
          {[
            'CBC Panel',
            'Lipid Profile',
            'Liver Function',
            'Kidney Function',
            'Thyroid Panel',
            'Glucose Test',
          ].map((template) => (
            <button
              key={template}
              onClick={() => navigate('/laboratory')}
              className="p-3 rounded-lg border border-border text-sm font-medium hover:bg-primary/5 hover:border-primary transition-all text-center"
            >
              {template}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
