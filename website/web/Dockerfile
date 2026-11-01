# DockGrove website: Next.js static export served by unprivileged nginx.
# Build context is website/ (not website/web) because the product policy comes
# from website/backend/product.mjs via scripts/prepare-product.mjs.
#
#   docker build -f website/web/Dockerfile -t dockgrove-web website
#   docker run --rm -p 8080:8080 -e API_UPSTREAM=http://host.docker.internal:8787 dockgrove-web

FROM node:24-bookworm-slim AS deps
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM deps AS build
ENV NEXT_TELEMETRY_DISABLED=1
COPY backend/product.mjs /src/backend/product.mjs
# tests/site.test.mjs checks that the Worker config serves out/ without paid bindings.
COPY wrangler.jsonc /src/wrangler.jsonc
COPY web/ /src/web/
# "prebuild" runs scripts/prepare-product.mjs (public/product.json), then
# `next build` with output: "export" writes the site to out/.
RUN npm run build

# `docker compose run --rm web-tests` — site tests against the export in out/.
FROM build AS test
CMD ["npm", "test"]

FROM nginxinc/nginx-unprivileged:1.28-alpine AS runtime
# Backend that answers /api/* and /downloads/*; substituted into the config at start.
ENV API_UPSTREAM=http://api:8787 \
    NGINX_ENVSUBST_FILTER=^API_UPSTREAM$
COPY web/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /src/web/out /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/"]
