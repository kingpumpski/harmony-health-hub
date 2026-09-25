import nodemailer from 'nodemailer';

const required = ['SMTP_HOST','SMTP_PORT','SMTP_SECURE','SMTP_USERNAME','SMTP_PASSWORD','SMTP_FROM_EMAIL','SMTP_TEST_RECIPIENT'];
for (const name of required) {
  if (!process.env[name]) throw new Error(`Missing required SMTP test secret: ${name}`);
}

const port = Number(process.env.SMTP_PORT);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('SMTP_PORT must be a valid TCP port');

const secure = process.env.SMTP_SECURE.toLowerCase() === 'true';
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port,
  secure,
  auth: { user: process.env.SMTP_USERNAME, pass: process.env.SMTP_PASSWORD },
  tls: { servername: process.env.SMTP_HOST },
});

try {
  await transporter.verify();
  const info = await transporter.sendMail({
    from: process.env.SMTP_FROM_EMAIL,
    to: process.env.SMTP_TEST_RECIPIENT,
    subject: 'Harmony Health Hub SMTP test',
    text: 'This is a controlled SMTP connectivity and delivery test for Harmony Health Hub. No patient or clinical information is included.',
    html: '<p>This is a controlled SMTP connectivity and delivery test for <strong>Harmony Health Hub</strong>.</p><p>No patient or clinical information is included.</p>',
  });
  console.log(JSON.stringify({ verified: true, sent: true, messageId: info.messageId }, null, 2));
} finally {
  transporter.close();
}
