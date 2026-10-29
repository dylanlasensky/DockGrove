# WaveDock website update without the pet redesign

Buildless HTML/CSS/JavaScript frontend for the existing `wavedock-preview` Cloudflare Worker. This publication excludes all rejected pet redesign artwork, the new gallery, and body-animation claims. A small roadmap note says the companion redesign remains in progress. The original full candidate checkout is untouched.

## Validate locally

```sh
node scripts/prepare-public.mjs
node tests/site.test.mjs --release
node tests/client.test.mjs
node tests/commerce.test.mjs
python3 -m http.server 8768 --bind 127.0.0.1 --directory public
```

The UI displays the proposed $9.99 one-time major-version offer from `backend/product.mjs`. The safe static snapshot always has `available:false`. Checkout, purchase lookup, recovery and activation require a separate configured test service; that service is not part of this deployment. No live payments are enabled.

## Publication boundary

Use only `wrangler deploy --config wrangler.jsonc` for this authorized static update. This retains the existing Worker/account and adds no D1, R2 or paid resources. `wrangler.commerce.jsonc`, backend code and migrations are implementation scaffolding for later test setup, not deployment instructions for this publication.

`public` contains no app ZIPs, development binaries, commercial binaries or pet redesign images. The old 0.8 download is omitted from this package; previously distributed MIT copies retain their rights. No changes are made to the historical license.

The homepage retains the app-replacement demo, automatic/light/dark preview, AI-usage limitations, pricing status and FAQs. Purchase/recovery pages explain the unavailable test configuration. Secrets remain out of browser storage; recovery fragments are cleared, redirects allow only Stripe checkout, and payment confirmation requires the server.

Website checks cover links, accessibility hooks, pet exclusion, no public downloads, central product configuration and static-only hosting. Browser review covers desktop/mobile, appearance, keyboard Replace/Undo/Escape and checkout unavailable states. See `docs/DESIGN-REVIEW-WEB.md` for the applied accessibility refinements. No production payment flow is claimed verified.

## Published static version

Published October 29, 2026 to https://wavedock-preview.limit-dylanlasensky.workers.dev using the existing Worker and zero bindings. Cloudflare version: `d0ff1466-eb19-49cb-abc9-2b180fd9606c`. Uploaded 14 packaged static files (10 changed assets). No commerce Worker, database, storage bucket or live payments were deployed.

Post-deploy browser review confirmed the app-focused page and disabled checkout. Live `product.json` reports amount 999 USD cents, test mode, `available:false`; both `/downloads/WaveDock-0.8.0.zip` and `/assets/companions/dragon.png` return HTTP 404. Local release checks, eight frontend behavior checks and eleven test-backend cases passed. Desktop dark and 390px light layouts, keyboard app replacement and Undo were verified.

## Original design restored

The current homepage is rebuilt from the 0.8 website: Find your flow hero, floating navigation, charcoal Dock illustration, scroll-driven window story, AI provider tabs, widget cards and layout/accent previews. The old pet card is replaced by the new searchable app picker. The proposed $9.99 offer is secondary near the footer with a disabled Coming soon control. That control cannot initiate checkout even if a test backend becomes available. Test-service explanations remain on the dedicated purchase/recovery pages. No pet artwork or app binary is included.

The homepage uses home.css/home.js; secure purchase/recovery and app-picker behavior stay in app.js, with utility pages using base.css. Accessibility improvements include scalable type, 44px controls, keyboard navigation, stronger secondary text and input contrast, and reduced-motion/transparency support.

Final restored-design publication: https://wavedock-preview.limit-dylanlasensky.workers.dev — Cloudflare version `5896ef10-bb84-46f6-827f-be3b0206d3ae`, October 29, 2026. This supersedes the intermediate d0ff1466 version. The deployed page was checked in Chrome and shows Find your flow, the restored sections, and disabled Coming soon. Static package: 16 files, no bindings, no pet artwork, no public app binaries.
