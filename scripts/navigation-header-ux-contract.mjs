import fs from 'node:fs';

const read = (p) => fs.readFileSync(p, 'utf8');
const sidebar = read('src/components/layout/Sidebar.tsx');
const header = read('src/components/layout/Header.tsx');
const search = read('src/lib/globalWorkspaceSearch.ts');
const app = read('src/App.tsx');
const pageHeader = read('src/components/layout/PageHeader.tsx');
const refreshButton = read('src/components/ui/RefreshButton.tsx');
const recordList = read('src/components/records/RecordList.tsx');
const failures = [];
const check = (name, condition) => { if (!condition) failures.push(name); };

check('Healthcare is the canonical clinical workspace label', sidebar.includes("'Healthcare'") && !sidebar.includes("'Clinical Operations'"));
check('Healthcare appears in global workspace search', search.includes("title:'Healthcare'") && !search.includes("title:'Clinical Operations'"));
check('normal users do not get a facility switcher in the header', !header.includes('get_user_facilities') && !header.includes('set_active_facility_context') && !header.includes('Active facility'));
check('facility sharing administration is routed', app.includes('/admin/facility-sharing') && app.includes('FacilityDataSharing'));
check('platform user management includes System Superuser', app.includes("path=\"/admin/users\"") && app.includes('system_superuser'));
check('facility attribution administration is routed', app.includes('/admin/facility-attribution') && app.includes('FacilityAttributionReview'));
check('shared refresh control is icon-only, circular and accessible', refreshButton.includes('rounded-full') && refreshButton.includes('aria-label={label}') && refreshButton.includes('RefreshCw'));
check('shared page header places primary action before refresh', pageHeader.indexOf('primaryAction') < pageHeader.indexOf('onRefresh') && pageHeader.includes('<RefreshButton'));
check('RecordList uses the shared refresh control and Add New before refresh', recordList.includes("RefreshButton") && recordList.indexOf('onAddNew') < recordList.indexOf('onRefresh'));


const layout = read('src/components/layout/MainLayout.tsx');
const routeLoading = read('src/components/system/RouteLoadingScreen.tsx');
check('authenticated layout provides a keyboard skip link and focusable main landmark', layout.includes('Skip to main content') && layout.includes('id="main-content" tabIndex={-1}'));
check('route-aware loading status is announced accessibly and motion respects reduced-motion preferences', routeLoading.includes('aria-live="polite"') && routeLoading.includes('motion-reduce:animate-none') && routeLoading.includes('Loading {moduleName}'));
check('mobile navigation closes when the route changes', layout.includes('setMobileNavOpen(false);') && layout.includes('[location.pathname]'));


const facilityOnboarding = read('src/pages/admin/PlatformFacilityOnboarding.tsx');
for (const [fieldId, label] of [
  ['facility-name', 'Facility / hospital name'],
  ['facility-code', 'Facility code (optional)'],
  ['facility-type', 'Facility type'],
  ['facility-district', 'District'],
  ['facility-region', 'Region'],
  ['facility-dhims2', 'DHIMS2 UID (optional)'],
]) {
  check(`facility onboarding field ${fieldId} has an associated visible label`,
    facilityOnboarding.includes(`htmlFor="${fieldId}"`) &&
    facilityOnboarding.includes(`id="${fieldId}"`) &&
    facilityOnboarding.includes(label));
}
check('facility onboarding organization name exposes organization autocomplete',
  facilityOnboarding.includes('name="facilityName" autoComplete="organization"'));
check('facility onboarding district and region expose address autocomplete tokens',
  facilityOnboarding.includes('name="facilityDistrict" autoComplete="address-level2"') &&
  facilityOnboarding.includes('name="facilityRegion" autoComplete="address-level1"'));

check('platform facility onboarding tolerates a missing role array without crashing',
  facilityOnboarding.includes("user?.roles?.includes('system_superuser') === true"));

if (failures.length) {
  console.error('Navigation/header UX contract failures:');
  failures.forEach((failure) => console.error('- ' + failure));
  process.exitCode = 1;
} else {
  console.log('Navigation/header UX contract passed.');
}
