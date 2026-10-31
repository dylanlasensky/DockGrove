# DockGrove commerce API (Cloudflare Worker) running locally under workerd via
# `wrangler dev` in local mode: local D1 (migrations applied at start), local R2,
# test-mode variables only. No secrets are baked in; see dev.mjs for the
# environment variables the container accepts.
#
#   docker build -f website/backend/Dockerfile -t dockgrove-api website
#   docker run --rm -p 8787:8787 dockgrove-api

FROM node:24-bookworm-slim
ENV NODE_ENV=production \
    WRANGLER_SEND_METRICS=false \
    CI=true \
    PORT=8787 \
    WRANGLER_PERSIST_DIR=/data
# workerd refuses to start without system CA certificates (outbound TLS to Stripe/Resend).
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g --no-audit --no-fund wrangler@4.156.0 \
    && mkdir -p /app /data && chown -R node:node /app /data
WORKDIR /app
COPY --chown=node:node backend/ ./backend/
COPY --chown=node:node migrations/ ./migrations/
USER node
VOLUME ["/data"]
EXPOSE 8787
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:'+process.env.PORT+'/api/product').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"]
CMD ["node", "backend/dev.mjs"]
