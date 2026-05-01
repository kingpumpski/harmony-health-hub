import { useMemo, useState } from 'react';
import { Users, CalendarDays, Clock, Activity, ShieldCheck } from 'lucide-react';

const departments = ['Doctors', 'Nurses', 'Lab Staff', 'Pharmacy Staff', 'Administration'];

export default function RosterGenerator() {
  const [department, setDepartment] = useState('Doctors');
  const [weekStart, setWeekStart] = useState(new Date().toISOString().slice(0, 10));

  const schedule = useMemo(() => [
    { day: 'Monday', shift: 'Morning', assigned: `${department} Team A` },
    { day: 'Tuesday', shift: 'Afternoon', assigned: `${department} Team B` },
    { day: 'Wednesday', shift: 'Night', assigned: `${department} Team C` },
    { day: 'Thursday', shift: 'Morning', assigned: `${department} Team D` },
    { day: 'Friday', shift: 'Afternoon', assigned: `${department} Team E` },
  ], [department]);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Roster Generator</h1>
          <p className="text-muted-foreground">Build staff schedules for hospital departments and shifts.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <CalendarDays className="w-4 h-4" /> Generate Roster
        </button>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="card-medical p-6">
          <div className="flex items-center gap-3 mb-4">
            <Users className="w-5 h-5 text-primary" />
            <div>
              <h2 className="text-lg font-semibold">Department</h2>
              <p className="text-sm text-muted-foreground">Select the team that needs a schedule.</p>
            </div>
          </div>
          <select value={department} onChange={(e) => setDepartment(e.target.value)} className="input-medical w-full">
            {departments.map((item) => (
              <option key={item} value={item}>{item}</option>
            ))}
          </select>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center gap-3 mb-4">
            <Clock className="w-5 h-5 text-success" />
            <div>
              <h2 className="text-lg font-semibold">Week Start</h2>
              <p className="text-sm text-muted-foreground">Choose the beginning of the roster week.</p>
            </div>
          </div>
          <input type="date" value={weekStart} onChange={(e) => setWeekStart(e.target.value)} className="input-medical w-full" />
        </div>

        <div className="card-medical p-6 bg-info/10 border-info border rounded-3xl">
          <div className="flex items-center gap-3 mb-4">
            <ShieldCheck className="w-5 h-5 text-info" />
            <div>
              <h2 className="text-lg font-semibold">Guidelines</h2>
              <p className="text-sm text-muted-foreground">Ensure balanced coverage and fair rotation.</p>
            </div>
          </div>
          <ul className="space-y-2 text-sm text-muted-foreground">
            <li>• Avoid repeating the same shift consecutively.</li>
            <li>• Reserve senior staff for high acuity days.</li>
            <li>• Keep day/night rotation consistent for fairness.</li>
          </ul>
        </div>
      </div>

      <div className="card-medical p-6">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-lg font-semibold">Generated Schedule</h2>
            <p className="text-sm text-muted-foreground">Preview the next roster for the selected department.</p>
          </div>
          <Activity className="w-5 h-5 text-primary" />
        </div>
        <div className="grid gap-3">
          {schedule.map((entry) => (
            <div key={entry.day} className="rounded-2xl border border-border p-4 flex items-center justify-between">
              <div>
                <p className="font-medium">{entry.day}</p>
                <p className="text-sm text-muted-foreground">{entry.shift} Shift</p>
              </div>
              <span className="text-sm font-medium text-foreground">{entry.assigned}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
