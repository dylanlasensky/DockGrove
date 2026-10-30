# DockGrove website

The public website is https://dockgrove.com. It retains the original Find your flow layout, with the owner's exact DockGrove artwork and all nine approved pixel companions. The website's pet previews use the actual app sprite sheets. Reduced Motion disables their animation.

Run with Node.js:

```sh
node scripts/prepare-public.mjs
node tests/site.test.mjs --release
node --test tests/client.test.mjs backend/*.test.mjs
python3 -m http.server 8769 --bind 127.0.0.1 --directory public
```

Deploy the static site with `wrangler deploy --config wrangler.jsonc`. The existing Worker service ID is retained for continuity. This static deployment creates no database, storage bucket, payment service or paid plan.

The planned price remains $9.99 once for major version 1, maintenance updates and three personal Macs. Checkout remains disabled; signing, notarization, owner-approved customer terms and live payment configuration are still pending. The separate test-commerce scaffolding is not deployed by the static config. No development app binaries or unprotected commercial downloads are placed in public assets.

The source and CI development artifacts include the approved pet implementation. See `docs/BRAND.md` for exact-logo extraction and storage compatibility details, and `docs/COMPANION-REVIEW.md` for the animation and validation contract.
