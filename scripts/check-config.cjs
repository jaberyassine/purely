const fs = require('node:fs');
const path = require('node:path');
const errors = [];
function walk(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => {
    if (['.git', 'node_modules', 'target', '.terraform', 'artifacts', '.validation', 'dist'].includes(e.name)) return [];
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : [p];
  });
}
for (const file of walk('.')) {
  if (!/\.(?:ya?ml|properties|jsx?|cjs|tf|json|md|conf)$/.test(file)) continue;
  const text = fs.readFileSync(file, 'utf8');
  if (/mongodb(?:\+srv)?:\/\/[^\s/]+:[^\s/]+@/.test(text)) errors.push(`${file}: embedded database credential`);
  if (/\.ya?ml$/.test(file) && /adminPassword:\s*\S+/.test(text)) errors.push(`${file}: embedded Grafana password`);
  if (/tag:\s*latest\b/.test(text)) errors.push(`${file}: mutable image release`);
  if (/\.tf$/.test(file) && /client_secret\s*=/.test(text)) errors.push(`${file}: client-secret provider authentication`);
}
for (const name of fs.readdirSync('k8s/charts')) {
  const p = `k8s/charts/${name}/templates/deployment.yaml`;
  const t = fs.readFileSync(p, 'utf8');
  for (const key of ['startupProbe:', 'readinessProbe:', 'livenessProbe:', 'readOnlyRootFilesystem: true', 'allowPrivilegeEscalation: false']) {
    if (!t.includes(key)) errors.push(`${p}: missing ${key}`);
  }
}
const registryValues = fs.readFileSync('k8s/charts/service-registry/values.yaml', 'utf8');
const registryPort = Number(registryValues.match(/^  port:\s*(\d+)/m)?.[1]);
for (const service of fs.readdirSync('microservice-backend', {withFileTypes: true}).filter(entry => entry.isDirectory())) {
  const config = path.join('microservice-backend', service.name, 'src/main/resources/application.yml');
  if (!fs.existsSync(config)) continue;
  const endpoint = fs.readFileSync(config, 'utf8').match(/defaultZone:\s*http:\/\/service-registry\.service-registry\.svc\.cluster\.local:(\d+)\/eureka/);
  if (endpoint && Number(endpoint[1]) !== registryPort) errors.push(`${config}: Eureka client port differs from the registry Service port`);
}
if (errors.length) { console.error(errors.join('\n')); process.exit(1); }
console.log('Configuration policy: PASS');
