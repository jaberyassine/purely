// Developer preview only: local UI, existing public demo APIs, verified HTTPS.
import { createServer } from 'vite';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const target = 'https://purely-demo-71154f86.eastus.cloudapp.azure.com';
const proxy = Object.fromEntries(['auth','user','product','category','cart','order','notification'].map(name => [
  '/' + name + '-service', { target, changeOrigin: true, secure: true },
]));
const server = await createServer({ root, server: { host: '127.0.0.1', port: 5191, strictPort: true, proxy } });
await server.listen();
console.log('\nPurely redesign: http://127.0.0.1:5191/');
console.log('The catalog uses the existing public demo APIs. Sign-in, cart and order actions affect your demo account.');
console.log('Keep this terminal open. Press Ctrl+C to stop. No AKS deployment was performed.');
