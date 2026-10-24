FROM eclipse-temurin:21-jdk AS jdk

FROM node:22-bookworm AS build
COPY --from=jdk /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk PATH=/opt/java/openjdk/bin:$PATH
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl rlwrap git ca-certificates \
 && curl -fsSL https://github.com/clojure/brew-install/releases/latest/download/linux-install.sh | bash \
 && corepack enable \
 && rm -rf /var/lib/apt/lists/*

# Empty LOGSEQ_REF = latest default branch (HEAD); otherwise a commit SHA, tag or branch.
ARG LOGSEQ_REPO=https://github.com/logseq/logseq.git
ARG LOGSEQ_REF=
WORKDIR /repo
RUN git init -q . \
 && git remote add origin "$LOGSEQ_REPO" \
 && git fetch --depth 1 origin "${LOGSEQ_REF:-HEAD}" \
 && git checkout -q FETCH_HEAD \
 && git rev-parse HEAD > /logseq-sha

WORKDIR /repo/deps/db-sync
RUN pnpm install --frozen-lockfile \
 && pnpm build:node-adapter \
 && CI=true pnpm prune --prod \
 && (cd /repo/node_modules/.pnpm/better-sqlite3@*/node_modules/better-sqlite3 && npm run install)

FROM node:22-bookworm-slim
WORKDIR /repo/deps/db-sync
COPY --from=build /repo/node_modules /repo/node_modules
COPY --from=build /repo/deps/db-sync/worker/dist ./worker/dist
COPY --from=build /repo/deps/db-sync/node_modules ./node_modules
COPY --from=build /logseq-sha /logseq-sha
ENV NODE_ENV=production \
    DB_SYNC_PORT=8787 \
    DB_SYNC_DATA_DIR=/data
RUN mkdir /data && chown node:node /data
VOLUME /data
EXPOSE 8787
USER node
CMD ["node", "worker/dist/node-adapter.js"]
