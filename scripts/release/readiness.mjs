import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

// Read source and public configuration only. Never read credentials or contact providers.
export function audit(sources, config = {}) {
  const code = [];
  const required = [
    ['backend', /SALES_MODE\s*===\s*['"]test['"]\s*&&\s*env\.STRIPE_SECRET_KEY/, 'Backend readiness only accepts test mode'],
    ['backend', /cs_test_/, 'Stripe sessions must validate the selected environment'],
    ['backend', /livemode\s*!==\s*false/, 'Stripe prices, sessions and webhooks only accept test objects'],
    ['backend', /environment:\s*['"]test['"]/, 'Signed entitlements hard-code the test environment'],
    ['native', /static let environment\s*=\s*"test"/, 'Native verifier and Keychain namespace hard-code test'],
    ['checkout', /product\.mode\s*===\s*"test"/, 'Checkout UI only supports test purchases'],
    ['home', /product\.mode\s*===\s*"test"/, 'Homepage purchase gating only supports test purchases'],
  ];
  for (const [file, pattern, reason] of required) {
    if (typeof sources[file] !== 'string') code.push(`Missing source: ${file}`);
    else if (pattern.test(sources[file])) code.push(reason);
  }
  const configuration = [];
  if (config.environment !== 'production') configuration.push('Explicit production environment is required');
  try {
    const url = new URL(config.origin);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/' || url.hostname.endsWith('.invalid')) throw Error();
  } catch { configuration.push('A valid production HTTPS service origin is required'); }
  // Removing a test-mode string is not evidence that production handling is correct.
  return {
    ready: false,
    code,
    configuration,
    verification: [
      'Independent review of explicit environment isolation across backend, native app and website',
      'Actual provider sandbox purchase, webhook fulfillment, recovery email and private download',
      'Native activation, restart/offline use, three-device limit, deactivation and refund/revocation checks',
      'Exact production artifact: Developer ID signature, hardened runtime, notarization and Gatekeeper',
      'Owner verification of production accounts, terms, sender and billing exposure',
    ],
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const paths = {backend:'website/backend/worker.mjs', native:'app/Sources/Licensing.swift', checkout:'website/web/src/lib/commerce.ts', home:'website/web/src/lib/home/product.ts'};
  const sources = {};
  for (const [name,path] of Object.entries(paths)) {
    try { sources[name] = await readFile(resolve(root,path),'utf8'); } catch { /* report missing source */ }
  }
  let config = {};
  if (process.argv[2]) {
    try { config = JSON.parse(await readFile(process.argv[2],'utf8')); }
    catch { console.error('Unable to read public release configuration.'); process.exit(2); }
  }
  console.log(JSON.stringify(audit(sources,config),null,2));
  process.exitCode = 2;
}
