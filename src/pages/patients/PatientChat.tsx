import { useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { MessageSquare, Send, User, ShieldCheck, AlertTriangle } from 'lucide-react';

export default function PatientChat() {
  const { patientId } = useParams();
  const { user } = useAuth();
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState([
    { sender: 'nurse', text: 'Patient is stable but still febrile. Please advise on next antibiotic choice.', time: '08:13' },
    { sender: 'physician', text: 'Continue current treatment and repeat temperature in 3 hours. Watch fluid balance.', time: '08:16' },
  ]);

  const isAllowed = useMemo(
    () => user?.role === 'nurse' || user?.role === 'practitioner' || user?.role === 'admin',
    [user],
  );

  const handleSend = (e: React.FormEvent) => {
    e.preventDefault();
    if (!message.trim()) return;
    setMessages((prev) => [...prev, { sender: user?.role === 'practitioner' ? 'physician' : 'nurse', text: message.trim(), time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }]);
    setMessage('');
  };

  if (!user) return null;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Patient Conversation</h1>
          <p className="text-muted-foreground">Secure client-specific chat for clinical teams. Only the record owner and attending clinicians may participate.</p>
        </div>
        <div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3">
          <MessageSquare className="w-5 h-5 text-primary" />
          <span className="text-sm text-muted-foreground">Client record chat is limited to {patientId || 'selected patient'}.</span>
        </div>
      </div>

      {!isAllowed && (
        <div className="rounded-3xl border border-warning/30 bg-warning/10 p-5 text-warning">
          Access denied. Nurse and physician roles may use the patient chat from the record view.
        </div>
      )}

      {isAllowed && (
        <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
          <div className="card-medical p-6 space-y-5">
            <div className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm uppercase tracking-[0.2em] text-muted-foreground">Open Patient Record</p>
                <h2 className="text-xl font-semibold">{patientId || 'Unknown patient'}</h2>
              </div>
              <div className="rounded-2xl bg-primary/10 px-3 py-2 text-primary text-sm">Connected</div>
            </div>
            <div className="space-y-4">
              {messages.map((msg, index) => (
                <div key={index} className={msg.sender === 'physician' ? 'rounded-3xl border border-primary/10 bg-primary/5 p-4' : 'rounded-3xl border border-border bg-background p-4'}>
                  <div className="flex items-center justify-between gap-3 mb-2 text-xs text-muted-foreground">
                    <span>{msg.sender === 'physician' ? 'Physician' : 'Nurse'}</span>
                    <span>{msg.time}</span>
                  </div>
                  <p>{msg.text}</p>
                </div>
              ))}
            </div>
            <form onSubmit={handleSend} className="space-y-3">
              <div>
                <label className="block text-sm font-medium mb-2">Write message</label>
                <textarea
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  className="input-medical min-h-[120px]"
                  placeholder="Add your note to the patient chat..."
                />
              </div>
              <button type="submit" className="btn-primary inline-flex items-center gap-2">
                <Send className="w-4 h-4" />
                Send Message
              </button>
            </form>
          </div>

          <div className="card-medical p-6 space-y-4">
            <div className="flex items-center gap-3">
              <ShieldCheck className="w-5 h-5 text-success" />
              <p className="text-sm text-muted-foreground">Private client-specific communication. This thread stays with the patient record.</p>
            </div>
            <div className="rounded-3xl border border-border p-4">
              <p className="font-medium">Use case</p>
              <p className="text-sm text-muted-foreground">Nurses report conditions in real time, physicians respond directly to the open record, and the chat remains scoped to that patient.</p>
            </div>
            <div className="rounded-3xl border border-border p-4 bg-background/80">
              <p className="font-medium">Next action</p>
              <p className="text-sm text-muted-foreground">Open the patient record and use this conversation tape to keep the care team aligned.</p>
            </div>
            <Link to="/patients" className="btn-secondary w-full text-center">
              Back to Patient Search
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
