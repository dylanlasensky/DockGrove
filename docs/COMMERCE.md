# WaveDock commerce candidate

This implementation is **test-mode only**. No Stripe account, webhook endpoint, database, bucket, email sender, live sale, or production deployment was created. Fixture tests are not provider acceptance.

## Offer and behavior

`website/backend/product.mjs` is the public source of truth: US $9.99 once, version 1 and maintenance updates, all companions, three personal Macs. Future major upgrades are not promised. Payment checkout is Stripe-hosted; WaveDock never handles card details. `GET /api/product` reports availability and public terms. Availability requires usable P-256 signing configuration, email configuration, and a nonempty private release object. Before creating a Checkout Session the server also retrieves the configured Stripe Price and rejects inactive, recurring, wrong-product, wrong-amount, wrong-currency or live Prices. Each purchase snapshots its offer so later configuration changes do not invalidate an outstanding checkout.

The browser obtains an opaque, HttpOnly/Secure/SameSite checkout cookie. The success page reads `/api/purchase` using that cookie. The server independently retrieves Stripe's session and validates test mode, payment mode/status, currency, total, subtotal, quantity, Price, Product, and price amount. A copied success URL grants nothing. Webhooks verify the original body, timestamp, and HMAC using Web Crypto. Successful fulfillment and event acknowledgment are stored in a D1 batch. Duplicate sessions produce one license. Refund/dispute markers prevent a delayed purchase event from resurrecting an entitlement. Any partial refund suspends the whole license; a dispute remains suspended even after closing until owner review. These are candidate policies requiring owner approval before sales.

Payment is limited to cards in this candidate; asynchronous failure/expiry events are still handled. The adapter pins the stable Stripe API version `2025-02-24.acacia` for response compatibility. Change it only with corresponding provider contract tests.

License keys are deterministic keyed HMAC values derived from purchase IDs, with only hashes indexed in D1. Keep `LICENSE_KEY_SECRET` stable; losing or rotating it without migration breaks recovery. Purchase email is stored for recovery. Device identity is a random installation UUID held in Keychain, not hardware tracking. The server stores its SHA-256 hash. A single conditional SQL statement enforces three active devices under concurrency.

Activation returns an ECDSA P-256 signed entitlement. The app embeds only an X9.63 public key and verifies the exact payload bytes with CryptoKit. Claims bind application, major version, test environment, device hash, issue time, and expiry. Cached entitlements permit **30 days offline**; the app attempts daily renewal while running. Refund/deactivation revocation is therefore eventual for offline Macs, bounded by that signed expiry. A temporary connection failure preserves still-valid access. Restore Apple Dock and Quit must remain available regardless of entitlement state.

Recovery uses an email link containing a 15-minute single-use token in the URL fragment. The frontend removes the fragment before exchange. Tokens are stored hashed; recovery responses do not reveal whether an email has a purchase. Rate limits apply to API calls and recovery, including a global per-email limit that survives source-IP rotation. Delivery uses an encrypted durable outbox with idempotent retry every five minutes; transient email-provider failures return the same generic acceptance. Expired messages are discarded, and no plaintext recovery tokens are stored in the queue. Checkout remains unavailable until email configuration is present. The current email adapter is Resend and requires a verified sender configured by the owner. No messages were sent during fixture testing.

## Endpoint contract

| Endpoint | Request | Result |
| --- | --- | --- |
| GET `/api/product` | None | Public policy and `available` |
| POST `/api/checkout` | `{}` | `{url}` and checkout cookie |
| GET `/api/purchase` | Checkout cookie | `status` and `licenseKey` only when paid |
| POST `/api/stripe/webhook` | Raw signed Stripe payload | Durable fulfillment acknowledgment |
| POST `/api/activate` | `{licenseKey,deviceId}` | `{entitlement:{payload,signature,keyId}}` |
| POST `/api/refresh` | Same | Renew active device entitlement |
| POST `/api/deactivate` | Same | Release this device slot |
| POST `/api/recover` | `{email}` | Generic acceptance; email if matching |
| POST `/api/recover/complete` | `{token}` | `{licenseKey}` after one-use verification |
| POST `/api/download` | `{licenseKey}` | Private R2 ZIP stream |

Errors use `{error}` and meaningful non-2xx statuses. Paths under `/api/*` and `/downloads/*` must run through the Worker before static assets. The commerce configuration blocks all direct download paths. It does not alter legacy files already distributed by the existing preview site.

## Owner setup and staging checks

1. Approve pricing, three-device policy, 30-day offline refresh, refund/dispute policy, and the separate commercial license transition before launch.
2. In an owned Stripe sandbox create a one-time USD 999-cent Price for WaveDock. Record Product and Price IDs. Do not use live keys.
3. Create a D1 database and private R2 release bucket within approved allowances. Fill binding identifiers in `website/wrangler.commerce.jsonc`; apply `website/migrations/0001_commerce.sql`. The existing `wrangler.jsonc` preview remains untouched.
4. Set the actual HTTPS staging origin. Configure secrets through Wrangler secret input, never source files or CLI argument values: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, a high-entropy `LICENSE_KEY_SECRET`, and `ENTITLEMENT_PRIVATE_JWK` (P-256 private JWK). Set `ENTITLEMENT_KEY_ID` for public-key rotation. Provision a separate verified email sender and secrets `RESEND_API_KEY`/`RECOVERY_FROM` if recovery email is to be exercised. No paid service is authorized automatically by this document.
5. Export only the corresponding P-256 public key as X9.63 bytes, standard Base64. Add public build configuration in the commercial app Info.plist: `WaveDockLicenseServerURL`, `WaveDockLicensePublicKeyBase64`, `WaveDockLicenseKeyID`. Never put the private JWK in the app. Native signature verification is independent from Apple's certificate and notarization work.
6. Run `zsh build.sh --commercial` to compile `dist/WaveDock-Commercial.app` with `WAVEDOCK_COMMERCIAL`. This mode requires `WAVEDOCK_LICENSE_SERVER_URL`, `WAVEDOCK_LICENSE_PUBLIC_KEY`, and `WAVEDOCK_LICENSE_KEY_ID`; `Scripts/ValidateLicenseConfig.swift` verifies an HTTPS root origin, a valid P-256 public key, and a nonempty key ID before compilation. A normal development build uses `zsh build.sh --development`, creates `dist/WaveDock.app`, intentionally requires no purchase, and uses the separate bundle identifier `com.dylan.wavedock.development`. It must never be uploaded as the paid artifact. `--commercial-qa` creates `dist/WaveDock-Commercial-QA.app` with a separate `com.dylan.wavedock.commercial-qa` bundle ID and allows missing public config solely to test the locked state. The commercial gate remains enabled; it is not an activation bypass. Development, QA, isolated tests, and commercial Keychain namespaces are separate. No runtime preference switches activation off. An owner tests commercial activation using an actual sandbox purchase; there is no universal owner license key.
7. Upload the verified commercial candidate into private R2 before offering checkout; the product remains unavailable without that release object. Register the staging webhook with the pinned API version and checkout session completed/async succeeded/async failed/expired, charge refunded, charge dispute created/closed event types. Use the webhook's own signing secret. Run Stripe CLI sandbox tests, then a complete sandbox browser checkout, license recovery, native activation, restart/offline verification, deactivation, fourth-device rejection, and refund/dispute tests.
8. Upload only a verified commercial candidate to private R2 at `RELEASE_OBJECT`. Verify direct static URLs fail and a valid purchase can download. Obtain final owner approval before any commercial site deployment or switch to real sales. This candidate deliberately rejects `sk_live_` and has no live-mode toggle; introducing live mode requires review, new test coverage, correct live public-key/environment configuration, and owner approval.
9. Malcolm handles Apple Developer ID signing, hardened runtime, notarization and release Gatekeeper validation separately. Preserve source-built local validation as distinct evidence.

Key rotation: retain the current key ID and verification public key until cached entitlements have expired, or extend the verifier with an explicit allowlisted public key ring before rotating. Do not silently substitute keys and invalidate customers. No actual production keys exist in this candidate.

## Validation

Run `node --test website/tests/commerce.test.mjs` with Node 24+ (uses node:sqlite as a local D1 adapter). The suite uses real SQLite constraints, Web Crypto HMAC/ECDSA and mocked Stripe/email transport. It exercises signature replay/tampering, wrong offer/environment, cookie-bound fulfillment, retries, three-device races, recovery one-use behavior, refund-before-payment ordering, private downloads and fail-closed missing configuration.

Compile and run `Tests/LicenseVerifierTests.swift` together with `Sources/Licensing.swift` and `Sources/LicensingTests.swift` using the installed Apple toolchain. Tests generate ephemeral keys and verify offline signatures, device binding, tampering, expiry, wrong app/version/environment and validity limits. They do not write a license to the user's Keychain.

Remaining external evidence: actual Stripe sandbox API calls, email delivery, D1/R2 deployment behavior, native end-to-end activation against staging, and the subsequent owner-approved live release. These cannot be claimed from fixtures.

Official references checked: https://docs.stripe.com/webhooks and https://docs.stripe.com/checkout/fulfillment .
