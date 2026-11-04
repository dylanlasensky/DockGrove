# Direct purchase release readiness

The website is published, but paid checkout is disabled. Explicit test/production handling is implemented. Actual provider validation and the signed commercial release remain unfinished. Owner credentials alone are insufficient.

Run `node --test scripts/release/readiness.test.mjs`, then `node scripts/release/readiness.mjs`. The audit reads source only, reports missing configuration separately and exits 2. It never grants launch approval: deleting a test-only check cannot constitute production verification. An optional public JSON file can specify `environment` and `origin`; never put secrets in it.

## Implemented preparation

- Backend mode is explicitly `test` or `production`. Unknown modes, mismatched Stripe secret/restricted-key prefixes, Checkout session IDs, prices, events, payment intents and charges fail closed. Signed claims use the configured environment.
- Apply both D1 migrations before use. The first configured request permanently assigns the database environment; an existing purchase database is classified as test. Production requires a separate database. Never manually relabel an existing test database.
- Use separate signing keys, key IDs, HMAC secrets, webhook secrets, D1 databases, private release buckets and sender credentials for each environment. Production key IDs must start with `production-`; test services reject that prefix. Legacy test license keys remain valid.
- Native `DOCKGROVE_LICENSE_ENVIRONMENT=test|production` is passed into Info.plist and the verifier. Commercial config validation requires an explicit mode. Production and test tokens are mutually rejected and Keychain namespaces are separate. Unknown modes cannot activate. Existing development fixtures remain compatible.
- Website `NEXT_PUBLIC_DOCKGROVE_COMMERCE_ENVIRONMENT` defaults to `test`. Both purchase helpers require the backend mode to match this build setting and `available:true`. Production copy is supported. The homepage Coming soon gate remains in place until an approved launch change; static product fallback is always unavailable.
- Offline fixtures exercise both environments, signed claims, mismatched objects, database reuse, activation, recovery and sales suspension. They do not establish provider acceptance.

## Disabled-by-default production gate

No deployed configuration has changed. Production checkout additionally requires `PRODUCTION_SALES_ENABLED=true` and a JSON `PRODUCTION_READINESS` record. Keep the switch false until the owner reviews real evidence. A sales pause still permits existing customers to refresh, recover and deactivate licenses.

The readiness record must bind `environment:production`, `origin`, `releaseObject`, `keyId`, and `priceId` to the actual configuration. It must include the exact archive `releaseSHA256` (64 lowercase hexadecimal characters), plus evidence references of at least eight characters for `providerSandbox`, `nativeActivation`, `recoveryDelivery`, `deviceLimitAndRevocation`, `signedNotarizedArtifact`, and `ownerApproval`. The private R2 object's custom `sha256` metadata must match that archive hash. Use an immutable release object name and independently hash the archive before upload.

These references are explicit owner attestations, not automatic proof that a provider or Apple approved anything. Fixture output must never be used to fill them. No approved record is supplied here. Changing a switch alone cannot make checkout available, and deleting a source pattern cannot make the offline audit approve launch.

## Remaining external verification

1. Actual Stripe sandbox checkout, signed webhook processing, refunds/disputes, private download and email recovery with the configured services.
2. Native CommercialQA activation, restart/offline use, expiration, three-device concurrency, deactivation and recovery against that provider environment.
3. A separately configured production commercial build with Developer ID signature, hardened runtime, notarization and Gatekeeper validation of the exact downloaded artifact.
4. Owner approval of seller identity, price, refund/support/tax/retention policies and customer terms. The current website terms remain explicitly draft. Update those approved terms and remove Coming soon in the launch change only after evidence is reviewed.

The production setup template is `website/wrangler.commerce.production.example.jsonc`. It is intentionally undeployable without owner bindings and has sales disabled. The existing test config and local container remain test-only. No credentials belong in either file.

## Owner prerequisites and consequences

| Service | Required owner action | Consequence and boundary |
| --- | --- | --- |
| Stripe | Activate/verify the business for live services; configure the actual product, price and webhook; provide scoped secrets through secret storage | Live mode can collect real payments. Sandbox account setup and actual provider testing precede launch. No account creation or agreements were completed here. |
| Cloudflare | Confirm existing D1/R2 access and approve any required subscription and usage exposure | R2 requires subscription checkout and can incur monthly usage charges beyond included allowances. Do not activate a new subscription under the no-spend constraint. Current remote subscription status is unverified. |
| Resend | Verify the sender domain and configure a suitable API credential | Recovery emails will disclose purchase recovery links to the addressed owner. Sender/domain access and delivery must be verified before sales. |
| Apple | Account Holder supplies the Developer ID identity through the normal signing workflow; notarize and test the exact artifact | Apple Development or ad-hoc signatures do not establish distributable Developer ID readiness. Do not export private signing keys into the repository. |
| Product owner | Confirm customer terms, refund policy, price and device allowance | Customer-facing obligations must match implemented fulfillment and revocation behavior. |

Official prerequisite references (current account status still requires inspection):

- [Stripe account setup and activation](https://docs.stripe.com/get-started/account/set-up)
- [Stripe key types and environment isolation](https://docs.stripe.com/keys)
- [Stripe testing](https://docs.stripe.com/testing)
- [Apple Developer ID distribution](https://developer.apple.com/developer-id/)
- [Cloudflare R2 setup](https://developers.cloudflare.com/r2/get-started/)
- [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/)
- [Resend free-tier domain verification](https://resend.com/changelog/three-domains-on-the-free-tier)

No keys or credentials were generated, no paid service was enabled, and checkout remains unavailable. Native notification badges and Handoff remain scoped app gaps rather than prerequisites for this direct purchase release.
