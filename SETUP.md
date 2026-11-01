# Setting up DockGrove locally and in CI/CD

DockGrove has two parts with separate pipelines:

| Part | Path | Built with | Workflow |
| --- | --- | --- | --- |
| macOS app | `app/` | Xcode (`xcodebuild`), macOS runners | `.github/workflows/build.yml` |
| Website + commerce API | `website/` | Docker, Node 24, Cloudflare Workers | `.github/workflows/web.yml` |

There are no shell scripts to run. The Mac app builds and tests through Xcode, and everything else runs through Docker. The Mac app has no Docker image because macOS apps can't be built or run in Linux containers. CI publishes it as zipped build artifacts instead.

## 1. Local setup

### Environment file

```sh
cp .env.example .env
```

Every value is optional. With an empty `.env`, the site and API run with checkout disabled, which matches the deployed test service before it's configured. `.env` is gitignored. Only ever use Stripe **test** keys in it: the API container refuses live keys and any `SALES_MODE` other than `test`.

### Website and API (Docker)

Requires Docker Desktop (or another Docker engine with Compose v2).

```sh
docker compose up --build                               # site http://localhost:8080, API http://localhost:8787
docker compose --profile test run --rm web-tests        # website tests against the static export
docker compose --profile test run --rm backend-tests    # commerce Worker tests
docker compose down -v                                  # stop and drop local D1/R2 state
```

If port 8080 or 8787 is taken, change `WEB_PORT` or `API_PORT` in `.env`. Nginx proxies `/api/*` and `/downloads/*` from the site to the API container. The API runs the real Worker (`website/backend/worker.mjs`) under `wrangler dev --local`, with D1 migrations applied at start.

Without Docker, from `website/web` with Node 24: `npm ci && npm run lint && npm run typecheck && npm run build && npm test`.

### macOS app (Xcode)

Requires macOS 14+ and Xcode. Open `app/DockGrove.xcodeproj` in Xcode, or use the command line:

```sh
cd app
xcodebuild test  -project DockGrove.xcodeproj -scheme "DockGrove Tests" -configuration Development -derivedDataPath .build/xcode -resultBundlePath .build/tests.xcresult
swift Scripts/CheckCoverage.swift .build/tests.xcresult                      # coverage gate CI enforces
xcodebuild build -project DockGrove.xcodeproj -scheme DockGrove -configuration Development -derivedDataPath .build/xcode
```

| Scheme / configuration | Purpose |
| --- | --- |
| **DockGrove Tests** (Development) | Offline XCTest regressions with code coverage |
| **DockGrove Native Tests** (Development) | UI test that renders every widget and checks window states; needs a logged-in desktop |
| **DockGrove** (Debug / Development) | Day-to-day build / universal ad-hoc-signed review build |
| **DockGrove Commercial** (Commercial) | Activation-enforced build; needs the `DOCKGROVE_LICENSE_*` values |
| CommercialQA configuration | Locked-state QA build under its own bundle identifier |
| **DockGrove StoreKit Testing** | Local StoreKit purchase testing without charges |

Live network checks are skipped unless you opt in, for example `TEST_RUNNER_DOCKGROVE_LIVE_TESTS=1 xcodebuild test …`. The project is generated from `app/project.yml`: after adding or removing files, run `cd app && xcodegen generate` (`brew install xcodegen`).

## 2. CI/CD on GitHub

### What runs

**`build.yml` (macOS app)** runs on pushes to `main`, `v*` tags, pull requests, and manually:
1. `build` (two independent passes): XCTest suite, then the coverage gate (`app/Scripts/CheckCoverage.swift`). The gate fails unless every function is 100% line-covered, apart from reviewed entries in `app/coverage-allowlist.txt`. It then builds the universal Development app, verifies its signature, Info.plist and architectures, runs the website/backend node tests, and uploads `DockGrove-development-universal-pass-N`.
2. `artifacts` (not on pull requests): builds Development and CommercialQA, plus Commercial when the license secrets exist. It uploads:
   - `DockGrove-review-builds`: app zips, dSYM zips and `SHA256SUMS.txt`, kept 30 days.
   - `DockGrove-commercial-private`: commercial zips, kept 7 days. Move them to private R2 storage; never publish them.
3. `native` (manual run with **native** ticked): the native rendering UI test, with renders attached to the result bundle.

**`web.yml` (website)** runs on `v*` tags, manually, and on pushes to `main` or pull requests that change `website/**`, `docker-compose.yml` or the workflow:
1. `test`: `npm ci`, lint, typecheck, build, website tests and backend tests. Uploads the `web-export` artifact.
2. `images`: builds `dockgrove-web` and `dockgrove-api`. Outside pull requests it pushes them to `ghcr.io/<owner>/` with `sha-<commit>`, branch, `latest` (default branch) and `X.Y.Z` / `X.Y` (on `v*` tags) tags.
3. `deploy` (pushes to `main` only): runs `wrangler deploy --config website/wrangler.jsonc` with the built export, through the `production` environment. It skips with a notice when `CLOUDFLARE_API_TOKEN` isn't set.

### One-time repository setup

1. **Actions permissions:** under Settings → Actions → General, allow GitHub Actions. Leave the default workflow permissions read-only; the workflows request `packages: write` only where they push images.
2. **Production environment:** under Settings → Environments, create `production`. Add required reviewers and limit deployment branches to `main` so deploys need approval.
3. **Cloudflare token:** in the Cloudflare dashboard → My Profile → API Tokens, create a token for the account in `website/wrangler.jsonc` with **Account · Workers Scripts · Edit**, plus **Zone · Workers Routes · Edit** and **Zone · Zone · Read** for `dockgrove.com`. Save it as the `CLOUDFLARE_API_TOKEN` secret **in the `production` environment**, not as a repository secret.
4. **Commercial app (optional):** add repository secrets `DOCKGROVE_LICENSE_SERVER_URL`, `DOCKGROVE_LICENSE_PUBLIC_KEY` and `DOCKGROVE_LICENSE_KEY_ID`. These are public values: an HTTPS origin, a base64 X9.63 P-256 public key, and its key id. Check them locally first:
   ```sh
   DOCKGROVE_LICENSE_SERVER_URL=… DOCKGROVE_LICENSE_PUBLIC_KEY=… DOCKGROVE_LICENSE_KEY_ID=… swift app/Scripts/ValidateLicenseConfig.swift
   ```
   Never add the private signing key (`ENTITLEMENT_PRIVATE_JWK`) to GitHub or the app. It belongs only to the commerce Worker, set with `wrangler secret put` (see `docs/COMMERCE.md`).
5. **Container images:** GHCR uses the built-in `GITHUB_TOKEN`, so no secret is needed. After the first push, set the package visibility under the repository's Packages if the images should be public.
6. **Branch protection (recommended):** require the `build`, `test` and `images` checks before merging to `main`.

### Secrets summary

| Name | Where | Required for |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | `production` environment secret | Website deploy |
| `DOCKGROVE_LICENSE_SERVER_URL` | Repository secret | Commercial app artifact |
| `DOCKGROVE_LICENSE_PUBLIC_KEY` | Repository secret | Commercial app artifact |
| `DOCKGROVE_LICENSE_KEY_ID` | Repository secret | Commercial app artifact |
| `GITHUB_TOKEN` | Built in | Image pushes to GHCR |

The commerce Worker's own secrets (Stripe, license, entitlement and email keys; see `.env.example`) are set on Cloudflare with `wrangler secret put`, not in GitHub. Live sales stay disabled until the owner approves them (`docs/COMMERCE.md`).

### Releasing

1. Merge to `main`. The website deploys after the `production` approval, and review builds of the app are attached to the run.
2. Tag a version (`git tag v1.0.0 && git push origin v1.0.0`). The web images get `1.0.0` / `1.0` tags, and the app artifacts are rebuilt from the tag.
3. Developer ID signing, notarization and the App Store submission happen outside CI. See `docs/MALCOLM-SIGNING-HANDOFF.md` and `docs/IN-APP-PURCHASES.md`.

## 3. Troubleshooting

- **Coverage gate fails:** the job log lists each function that isn't fully covered. Add tests. Use `app/coverage-allowlist.txt` only for code that can't run without real OS state, and give a reason (`File.swift: function # reason`). Stale entries also fail the gate.
- **`xcodebuild` asks for a provisioning profile:** use the Development, Commercial or CommercialQA configuration (ad-hoc signed, no entitlements). Debug and Release use your Apple Development team; WeatherKit needs that provisioned build.
- **Docker port already in use:** set `WEB_PORT` / `API_PORT` in `.env`.
- **API container exits at start:** it refuses `SALES_MODE` other than `test` and Stripe keys that don't start with `sk_test_`.
- **Deploy job skipped:** `CLOUDFLARE_API_TOKEN` is missing from the `production` environment.
