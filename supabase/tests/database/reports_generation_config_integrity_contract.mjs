import fs from 'node:fs';

const source = fs.readFileSync('src/lib/reportsCenter.ts', 'utf8');

const required = [
  'const persistedConfigs = await listFacilityConfigs(facilityId);',
  "const enabled = persistedConfigs.filter((config) => config.is_enabled && config.report?.frequency === 'monthly');"
];

for (const marker of required) {
  if (!source.includes(marker)) throw new Error(`Report generation integrity guard missing: ${marker}`);
}

if (source.includes("const enabled = configs.filter((config) => config.is_enabled && config.report?.frequency === 'monthly');")) {
  throw new Error('Report generation still trusts client-supplied configuration objects');
}

console.log('Report generation configuration integrity contract passed');
