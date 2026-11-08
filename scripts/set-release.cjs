const fs = require('node:fs');
const path = require('node:path');
const [sha, registry] = process.argv.slice(2);
if (!/^[a-f0-9]{40}$/.test(sha || '')) throw new Error('A full Git commit SHA is required');
if (!/^[a-z0-9]+\.azurecr\.io$/.test(registry || '')) throw new Error('Expected an ACR login server');
for (const service of fs.readdirSync('k8s/charts')) {
  const file = path.join('k8s/charts', service, 'values.yaml');
  const image = service === 'frontend' ? 'frontend-app' : service;
  const text = fs.readFileSync(file, 'utf8')
    .replace(/^  tag:.*$/m, `  tag: ${sha}`)
    .replace(/^  repository:.*$/m, `  repository: ${registry}/${image}`);
  fs.writeFileSync(file, text);
}
console.log(`Set 10 Helm charts to ${sha}`);
