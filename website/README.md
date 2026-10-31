# DockGrove website

The public website is https://dockgrove.com. It retains the original Find your flow layout, with the owner's exact DockGrove artwork and all nine approved pixel companions. The website's pet previews use the actual app sprite sheets. Reduced Motion disables their animation.

The site is a Next.js app (React, TypeScript, Tailwind CSS) in `web/`, exported as static files to `web/out/`. `public/` holds the original static pages it was converted from, kept as the visual reference.

Run with Docker (site on http://localhost:8080, Worker API on http://localhost:8787, `/api/*` proxied):

```sh
docker compose up --build
docker compose --profile test run --rm web-tests
docker compose --profile test run --rm backend-tests
```

Or with Node.js 24 from `web/`: `npm ci && npm run lint && npm run typecheck && npm run build && npm test`.

Deploy the static site with `wrangler deploy --config wrangler.jsonc` after building `web/out/` (CI does this on `main` when `CLOUDFLARE_API_TOKEN` is set in the `production` environment). The existing Worker service ID is retained for continuity. This static deployment creates no database, storage bucket, payment service or paid plan.

The planned price remains $9.99 once for major version 1, maintenance updates and three personal Macs. Checkout remains disabled; signing, notarization, owner-approved customer terms and live payment configuration are still pending. The separate test-commerce scaffolding is not deployed by the static config. No development app binaries or unprotected commercial downloads are placed in public assets.

The source and CI development artifacts include the approved pet implementation. See [`docs/BRAND.md`](../docs/BRAND.md) for exact-logo extraction and storage compatibility details, and [`docs/COMPANION-REVIEW.md`](../docs/COMPANION-REVIEW.md) for the animation and validation contract.
