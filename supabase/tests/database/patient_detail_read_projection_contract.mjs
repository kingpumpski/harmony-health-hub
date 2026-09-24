import fs from 'node:fs';

const healthApi = fs.readFileSync('src/lib/healthApi.ts', 'utf8');
const projection = "select('id,patient_code,first_name,last_name,date_of_birth,gender,email,phone,address,city,ghana_card_number,blood_group,genotype,allergies,chronic_conditions,insurance_provider,insurance_number,insurance_group_number,insurance_expiry,emergency_contact_name,emergency_contact_phone,emergency_contact_relation,status')";
if (!healthApi.includes(projection)) throw new Error('Patient detail explicit projection missing');
if (healthApi.includes(".from('patients').select('*')")) throw new Error('Broad patient detail select remains');
console.log('Patient detail read projection contract passed');
