import fs from 'node:fs';

const app = fs.readFileSync('src/App.tsx', 'utf8');

const requiredRoutes = [
  ['/dashboard', 'Dashboard'],
  ['/patients', 'PatientSearch'],
  ['/patients/:patientId', 'PatientHub'],
  ['/appointments', 'Appointments'],
  ['/encounters', 'Encounters'],
  ['/clinical-operations', 'ClinicalOperations'],
  ['/ward-bed-board', 'WardBedBoard'],
  ['/nursing-handover', 'NursingHandover'],
  ['/insurance-claims', 'InsuranceClaims'],
  ['/emergency-board', 'EmergencyBoard'],
  ['/theatre-board', 'TheatreBoard'],
  ['/transfusion-board', 'TransfusionBoard'],
  ['/laboratory', 'Laboratory'],
  ['/imaging', 'Imaging'],
  ['/pharmacy', 'Pharmacy'],
  ['/medications', 'MedicationAdministration'],
  ['/inpatients', 'AdmissionManagement'],
  ['/maternity', 'Maternity'],
  ['/fertility', 'Fertility'],
  ['/dental', 'Dental'],
  ['/ophthalmology', 'Ophthalmology'],
  ['/telemedicine', 'Telemedicine'],
  ['/billing', 'Billing'],
  ['/reports', 'ReportsCenter'],
  ['/public-health', 'ReportsCenter'],
  ['/roster', 'RosterGenerator'],
  ['/ai-clinical', 'AIClinicalHub'],
  ['/patient-portal', 'PatientPortal'],
  ['/notifications', 'Notifications'],
  ['/admin/offline-sync', 'OfflineSyncCenter'],
  ['/admin/next-gen-platform', 'NextGenPlatformControlCenter'],
];

for (const [route, component] of requiredRoutes) {
  const routePattern = new RegExp(`<Route\\s+path=["']${route.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')}["']\\s+element={<${component}\\s*/?>}`);
  if (!routePattern.test(app)) {
    throw new Error(`Required application route is missing or disconnected: ${route} -> ${component}`);
  }
}

for (const component of new Set(requiredRoutes.map(([, component]) => component))) {
  if (!app.includes(`const ${component} = lazy(`)) {
    throw new Error(`Required route component is not lazy-loaded: ${component}`);
  }
}

if (!app.includes('<Route element={<MainLayout />}>')) {
  throw new Error('Clinical application routes are not mounted beneath MainLayout');
}
if (!app.includes('<AuthProvider>')) {
  throw new Error('Application routes are not mounted beneath AuthProvider');
}
if (!app.includes('<AppErrorBoundary>')) {
  throw new Error('Application root is missing the runtime error boundary');
}

console.log(`Next-gen route surface contract passed: ${requiredRoutes.length} critical routes remain connected to their canonical page components, lazy loading, authenticated layout, and application error boundary.`);
