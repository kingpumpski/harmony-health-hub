import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Bell, AlertTriangle, CheckCircle2, Info, AlertCircle } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Link } from 'react-router-dom';

interface NotificationRow {
  id: string;
  title: string;
  message: string;
  severity: string;
  category: string | null;
  link: string | null;
  related_patient_id: string | null;
  is_read: boolean;
  created_at: string;
  recipient_role: string | null;
  recipient_user_id: string | null;
}

const severityIcon = (sev: string) => {
  if (sev === 'critical') return <AlertTriangle className="w-5 h-5 text-critical animate-pulse" />;
  if (sev === 'warning') return <AlertCircle className="w-5 h-5 text-warning" />;
  if (sev === 'success') return <CheckCircle2 className="w-5 h-5 text-success" />;
  return <Info className="w-5 h-5 text-info" />;
};

export default function Notifications() {
  const { user } = useAuth();
  const [items, setItems] = useState<NotificationRow[]>([]);
  const [filter, setFilter] = useState<'all' | 'unread'>('all');
  const db = supabase as any;

  const load = useCallback(async () => {
    const { data, error } = await db.rpc('get_workflow_notifications', { _limit: 200 });
    if (!error) {
      const rows = (data ?? []) as NotificationRow[];
      setItems(filter === 'unread' ? rows.filter((row) => !row.is_read) : rows);
    }
  }, [filter]);

  useEffect(() => {
    void load();
    const channel = supabase
      .channel('notif-page')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notifications' }, () => void load())
      .subscribe();
    return () => { void supabase.removeChannel(channel); };
  }, [load]);

  const markRead = async (id: string) => {
    const { error } = await db.rpc('mark_notification_read', { _notification_id: id });
    if (!error) void load();
  };

  const markAllRead = async () => {
    const ids = items.filter((n) => !n.is_read).map((n) => n.id);
    if (!ids.length) return;
    const { error } = await db.rpc('mark_notifications_read', { _notification_ids: ids });
    if (!error) void load();
  };

  if (!user) return null;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold flex items-center gap-2">
            <Bell className="w-6 h-6 text-primary" /> Notifications
          </h1>
          <p className="text-muted-foreground">Real-time alerts for your role and personal items.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <button onClick={() => setFilter('all')} className={cn('px-3 py-1.5 rounded-lg text-sm', filter === 'all' && 'bg-primary text-primary-foreground')}>All</button>
          <button onClick={() => setFilter('unread')} className={cn('px-3 py-1.5 rounded-lg text-sm', filter === 'unread' && 'bg-primary text-primary-foreground')}>Unread</button>
          <button onClick={() => void markAllRead()} className="btn-ghost text-sm">Mark all read</button>
        </div>
      </div>

      <div className="card-medical divide-y divide-border">
        {items.length === 0 && <p className="p-6 text-center text-muted-foreground">No notifications.</p>}
        {items.map((n) => {
          const inner = (
            <div className={cn(
              'p-4 flex items-start gap-3 hover:bg-muted/50 transition-colors',
              !n.is_read && 'bg-primary/5',
              n.severity === 'critical' && 'border-l-4 border-l-critical',
            )}>
              {severityIcon(n.severity)}
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2">
                  <p className="font-medium">{n.title}</p>
                  <span className="text-xs text-muted-foreground whitespace-nowrap">{new Date(n.created_at).toLocaleString()}</span>
                </div>
                <p className="text-sm text-muted-foreground mt-0.5">{n.message}</p>
                {n.category && <span className="inline-block mt-2 text-[10px] uppercase tracking-wider text-muted-foreground bg-muted px-2 py-0.5 rounded">{n.category}</span>}
              </div>
            </div>
          );
          return (
            <div key={n.id} onClick={() => !n.is_read && void markRead(n.id)}>
              {n.link ? <Link to={n.link}>{inner}</Link> : inner}
            </div>
          );
        })}
      </div>
    </div>
  );
}
