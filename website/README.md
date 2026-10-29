# WaveDock website

Buildless HTML/CSS/JavaScript. Serve `public/` with a static server for local QA.
No framework, database, server handler, analytics or paid APIs.

`wrangler deploy` from this directory publishes only `public/` as an independent
Cloudflare static-assets project. No Worker script or `run_worker_first` is configured.
Static asset requests and storage are free under Cloudflare's published pricing.
No custom domain, paid subscription, or existing application is modified.

Before deployment, build and validate WaveDock twice, then copy the packaged app to
`public/downloads/WaveDock-0.6.0.zip`. Downloads are generated artifacts and ignored
by Git. Run `node tests/site.test.mjs` twice; use `--release` to also validate the ZIP.

Design references studied October 28, 2026:
- Apple MacBook Pro PROLED XDR page: large product type, persistent contextual nav,
  scroll reveals, focused product stages and compact gallery controls.
- CoolDock home: floating navigation, generous spacing, product demonstrations,
  categorized feature sections and expandable FAQ.

WaveDock uses its own wave mark, typography, artwork, product illustrations and copy.
No reference site's source or assets were copied. Demos are labeled sample data.
Motion respects reduced-motion preferences, with no scroll trapping or autoplay video.
