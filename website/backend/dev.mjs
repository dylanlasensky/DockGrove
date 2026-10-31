// Container entrypoint for the commerce Worker (see backend/Dockerfile).
// 1. Applies website/migrations to the local D1 database.
// 2. Starts `wrangler dev` in local mode (workerd) on 0.0.0.0:$PORT.
//
// Configuration is read from the process environment and forwarded to the
// Worker as bindings. Everything is optional; without the secrets the API
// answers /api/product with available:false and 503 for checkout, exactly as
// the deployed test service does before the owner configures it.
//
//   PUBLIC_ORIGIN           Origin the site is served from (default http://localhost:8080)
//   STRIPE_PRICE_ID         price_... (test mode)
//   STRIPE_PRODUCT_ID       prod_...  (test mode)
//   ENTITLEMENT_KEY_ID      Key id published to the app (default test-1)
//   RELEASE_OBJECT          Object name in the local R2 bucket (default DockGrove-1.zip)
//   STRIPE_SECRET_KEY       sk_test_... only; live keys are refused
//   STRIPE_WEBHOOK_SECRET   whsec_...
//   LICENSE_KEY_SECRET      >= 32 characters
//   ENTITLEMENT_PRIVATE_JWK EC P-256 private key as JSON
//   RESEND_API_KEY          Resend API key for recovery email
//   RECOVERY_FROM           From address for recovery email
//   PORT                    Listen port (default 8787)
//   WRANGLER_PERSIST_DIR    Where local D1/R2 state lives (default /data)
//
// Put them in website/backend/.dev.vars (gitignored) for `docker compose up`.
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const config = fileURLToPath(new URL('./wrangler.local.jsonc', import.meta.url));
const persist = process.env.WRANGLER_PERSIST_DIR || '/data';
const port = process.env.PORT || '8787';
const forwarded = [
  'SALES_MODE', 'PUBLIC_ORIGIN', 'STRIPE_PRICE_ID', 'STRIPE_PRODUCT_ID', 'ENTITLEMENT_KEY_ID', 'RELEASE_OBJECT',
  'STRIPE_SECRET_KEY', 'STRIPE_WEBHOOK_SECRET', 'LICENSE_KEY_SECRET', 'ENTITLEMENT_PRIVATE_JWK', 'RESEND_API_KEY', 'RECOVERY_FROM',
];

function refuse(message) { console.error(`dev.mjs: ${message}`); process.exit(2); }
if (process.env.SALES_MODE && process.env.SALES_MODE !== 'test') refuse('this container only runs SALES_MODE=test');
if (process.env.STRIPE_SECRET_KEY && !process.env.STRIPE_SECRET_KEY.startsWith('sk_test_')) refuse('STRIPE_SECRET_KEY must be a Stripe test key (sk_test_...)');

const vars = forwarded.filter(name => process.env[name] !== undefined && process.env[name] !== '').flatMap(name => ['--var', `${name}:${process.env[name]}`]);
console.log(`dev.mjs: forwarding ${vars.length / 2} variable(s): ${forwarded.filter(n => process.env[n]).join(', ') || '(none)'}`);

const migrate = spawnSync('wrangler', ['d1', 'migrations', 'apply', 'DB', '--local', '--config', config, '--persist-to', persist], { stdio: 'inherit' });
if (migrate.status !== 0) refuse(`migrations failed (exit ${migrate.status})`);

const dev = spawn('wrangler', [
  'dev', '--config', config, '--local', '--ip', '0.0.0.0', '--port', port, '--persist-to', persist,
  '--show-interactive-dev-session', 'false', '--test-scheduled', ...vars,
], { stdio: 'inherit' });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => dev.kill(signal));
dev.on('exit', code => process.exit(code ?? 1));
