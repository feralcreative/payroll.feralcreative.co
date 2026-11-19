FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY server.js ./
COPY lib ./lib
COPY public ./public

ENV NODE_ENV=production
# Auth is Cloudflare Access at the edge. This makes the container refuse any
# request that did not come through it, so a tunnel misconfiguration fails closed.
ENV REQUIRE_ACCESS_HEADER=1

USER node
EXPOSE 8118

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8118/healthz >/dev/null || exit 1

CMD ["node", "server.js"]
