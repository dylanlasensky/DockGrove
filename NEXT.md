# Next steps

What is left before DockGrove ships. Items here need the owner of the Cloudflare account that hosts
dockgrove.com (`222552fe7a46283461a3d7a48edca0e1`) or the GitHub repo settings. They cannot be done from
the repository.

Last checked: 2026-11-03.

## dockgrove.com (Cloudflare)

### 1. Turn on automatic deploys — blocking
The Website workflow's "Deploy to Cloudflare" job is skipped on every push to `main`, because the
`production` environment has no `CLOUDFLARE_API_TOKEN`. The job still shows green. Since this change it
logs a warning: "The live site was NOT updated". Until the token is added, someone has to deploy by hand
(`npx wrangler deploy --config website/wrangler.jsonc` after `npm run build` in `website/web`).

1. In Cloudflare, go to My Profile › API Tokens › Create Token › "Edit Cloudflare Workers". Limit it to account
   `222552fe…` and the zone `dockgrove.com`.
2. In GitHub, go to Settings › Environments › `production` › Add secret `CLOUDFLARE_API_TOKEN`.
3. Re-run the latest Website workflow on `main`. The deploy step should print a version ID.

### 2. Stop email spoofing
The domain has no MX, SPF or DMARC records, so anyone can send mail claiming to be @dockgrove.com.
If the domain sends no mail yet, add these under DNS › Records:

| Type | Name | Content |
|---|---|---|
| MX | `@` | `.` (priority 0, a "null MX") |
| TXT | `@` | `v=spf1 -all` |
| TXT | `_dmarc` | `v=DMARC1; p=reject; adkim=s; aspf=s` |

Before the purchase or recover flows send email, replace these with the sending provider's SPF and DKIM
records. Relax DMARC to `p=quarantine` while you test.

### 3. Enable DNSSEC
The registrar is Cloudflare, so this is one click: DNS › Settings › DNSSEC › Enable. There is no DS record to
copy anywhere.

### 4. Redirect www to the main domain
`www.dockgrove.com` serves the same page instead of redirecting. The canonical tag already points at
`https://dockgrove.com`, so search is fine, but a redirect is cleaner:
Rules › Redirect Rules › template "Redirect from WWW to root" (301, keep the query string).

### 5. Make HTTPS strict
The site now sends `Strict-Transport-Security: max-age=31536000; includeSubDomains`. In SSL/TLS, also check:
- Edge Certificates: **Always Use HTTPS** is on. HTTP already 301s, so it probably is.
- **Minimum TLS Version** is 1.2.
- Add a CAA record so only Cloudflare's certificate authorities can issue certificates for the domain. SSL/TLS ›
  Edge Certificates shows which ones Cloudflare uses.

### 6. After the first deploy from `main`
`workers_dev` is now `false`, so the next deploy removes the `wavedock-preview.<subdomain>.workers.dev`
copy of the site. Only dockgrove.com and www serve it. Check afterwards that both still return 200.

## Sales backend
`/purchase` shows "Test mode", and `/api/*` returns 404. `website/wrangler.commerce.jsonc` is a test
setup and isn't deployed. To go live, the owner needs to:
- Create the D1 database and R2 bucket, then fill in `database_id`. It is currently `OWNER_CONFIG_REQUIRED`.
- Set `PUBLIC_ORIGIN` to `https://dockgrove.com` (it is currently `example.invalid`), `SALES_MODE`, and the Stripe
  price and product IDs.
- Add the secrets the Worker reads: the Stripe keys, the webhook secret and the entitlement signing key.
- Route `/api/*` and `/downloads/*` on dockgrove.com to that Worker.
- See `SETUP.md` for the full list.

## Later
- **Worker name:** the Worker is still called `wavedock-preview`, from the old WaveDock name. Renaming it creates a
  new Worker, so move the custom domains over and delete the old one in the same change.
- **CSP:** the policy allows `'unsafe-inline'` scripts because the Next.js static export uses inline
  bootstrap scripts. Switching to hashes or a nonce would tighten it.

## App (open PRs)
- [#15](https://github.com/dylanlasensky/DockGrove/pull/15): notch hover options, Apps-style chooser,
  Mac Dock menus, Dock controls and Claude plan limits.
- [#16](https://github.com/dylanlasensky/DockGrove/pull/16): settings audit doc. Stacked on #15, so merge
  #15 first.
- **Product decisions still open:**
  - Should the chooser's Icons/List switch move into a "…" menu?
  - Category names.
  - Should ⌥⌘D hide all Docks or only the main one?
  - Should AirDrop in the notch close when the pointer leaves?
  - Should Esc require Accessibility permission?
  - Where should the Size panel go?
  - Should presets turn Fit off?
- **Known gaps:**
  - The Studio Size preview is one tile narrower than the real Dock, because it leaves out the Applications stack.
  - The Claude card's 5-hour row hasn't been checked against real `/usage` output, since Claude Code isn't
    printing a 5-hour line yet.
