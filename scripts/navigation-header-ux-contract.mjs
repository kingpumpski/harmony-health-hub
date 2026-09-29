import fs from 'node:fs';
import path from 'node:path';

const read = (p) => fs.readFileSync(p, 'utf8');
const header = read('src/components/layout/Header.tsx');
const sidebar = read('src/components/layout/Sidebar.tsx');
const mainLayout = read('src/components/layout/MainLayout.tsx');

const settingsPage = read('src/pages/admin/Settings.tsx');
const reportsCenter = read('src/pages/ReportsCenter.tsx');

const failures = [];
const assert = (name, condition, detail) => {
  if (!condition) failures.push(`${name}: ${detail}`);
};

assert('notification configuration belongs to system settings',
  settingsPage.includes('Notification Control Plane') &&
  settingsPage.includes('Email Service Configuration') &&
  settingsPage.includes('Custom SMTP') &&
  settingsPage.includes('update_facility_notification_configuration'),
  'System Settings must own notification control-plane and SMTP configuration');

assert('reports center contains reporting only',
  !reportsCenter.includes('Notification Control Plane') &&
  !reportsCenter.includes('Notification onboarding') &&
  !reportsCenter.includes('facility_notification_config') &&
  !reportsCenter.includes('set_facility_notification_provider'),
  'Reports Center must not render or own notification configuration');

assert('admin and IT admin navigation exposes system settings',
  sidebar.includes("item(Settings, 'System Settings', '/admin/settings', 'system_settings')") &&
  header.includes('to="/admin/settings"') &&
  header.includes('user.role === "it_admin"'),
  'Administrators and IT administrators must have an explicit system settings entry point');

assert('global search is in the header action cluster',
  header.includes('aria-label="Global search"') &&
  header.includes('searchOpen') &&
  header.includes('ml-auto flex shrink-0 items-center'),
  'Header must expose search as a compact action alongside notifications/theme/account controls');

assert('header has no standalone role badge',
  !header.includes('Role command center') &&
  !header.includes('aria-label="Active operational role"'),
  'The header must not render a standalone active-role badge');

assert('header has no greeting',
  !header.includes('const greeting') &&
  !header.includes('Welcome '),
  'Greeting text must not be rendered by Header');

assert('header retains account profile and sign-out actions',
  header.includes('to="/profile"') &&
  header.includes('Sign out') &&
  header.includes('aria-label="Account menu"'),
  'Profile and sign-out must remain available from the account menu');

assert('sidebar replaces account actions with role and connectivity',
  !sidebar.includes('to="/profile"') &&
  !sidebar.includes('Sign out') &&
  sidebar.includes('user.role.replaceAll') &&
  sidebar.includes("online ? 'Online' : 'Offline mode'") &&
  sidebar.includes('<Cloud') &&
  sidebar.includes('<CloudOff'),
  'Sidebar footer must show role plus live online/offline state instead of profile/sign-out controls');

assert('sidebar connectivity listens to browser connectivity changes',
  sidebar.includes('navigator.onLine') &&
  sidebar.includes('online') &&
  sidebar.includes('online') &&
  sidebar.includes('addEventListener'),
  'Connectivity indicator must derive from browser online/offline state and react to changes');

assert('workspace greeting is transient and outside Header',
  mainLayout.includes('role="status"') &&
  mainLayout.includes('aria-live="polite"') &&
  mainLayout.includes('setShowGreeting(false)') &&
  mainLayout.includes('setTimeout'),
  'Workspace-ready greeting must be a transient status message managed by MainLayout');

const dashboardDir = 'src/pages/dashboard';
for (const file of fs.readdirSync(dashboardDir).filter((name) => name.endsWith('.tsx'))) {
  const source = read(path.join(dashboardDir, file));
  if (source.includes('RefreshCw')) {
    assert(`refresh control is icon-only in ${file}`,
      !source.includes('>Refresh<') &&
      !source.includes('>Refresh </') &&
      !source.includes('>Refresh dashboard<') &&
      !source.includes('>Refresh Dashboard<'),
      'Refresh controls using RefreshCw must not render a visible refresh label');
  }
}

if (failures.length) {
  console.error('Navigation/header UX contract failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log('Navigation/header UX contract passed');
}
