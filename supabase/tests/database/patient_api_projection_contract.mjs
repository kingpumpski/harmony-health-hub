import fs from 'node:fs';
const p=fs.readFileSync('src/lib/healthApi.ts','utf8');
const checks=[
  ['patient insert uses explicit response projection', /\.from\('patients'\)\.insert\(insertRow as any\)\.select\('id,patient_code,first_name,last_name,date_of_birth,gender,email,phone,address,city,ghana_card_number,blood_group,genotype,allergies,chronic_conditions,insurance_provider,insurance_number,insurance_group_number,insurance_expiry,emergency_contact_name,emergency_contact_phone,emergency_contact_relation,status'\)/],
  ['patient update uses explicit response projection', /\.from\('patients'\)\.update\(cleanRow as any\)\.eq\('id', id\)\.select\('id,patient_code,first_name,last_name,date_of_birth,gender,email,phone,address,city,ghana_card_number,blood_group,genotype,allergies,chronic_conditions,insurance_provider,insurance_number,insurance_group_number,insurance_expiry,emergency_contact_name,emergency_contact_phone,emergency_contact_relation,status'\)/],
  ['no broad patient mutation response reads', !p.includes(".insert(insertRow as any).select().single()") && !p.includes(".update(cleanRow as any).eq('id', id).select().single()')]
];
for(const [n,ok] of checks) if(!ok) throw new Error('Patient API projection contract failed: '+n);
console.log('Patient API projection contract passed');
