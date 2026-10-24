# logseq-db-sync-docker

Docker image of the self-hosted Node adapter of `deps/db-sync` from [logseq/logseq](https://github.com/logseq/logseq).
The Logseq source is cloned at build time; nothing from upstream is copied here.

## Build

```bash
# latest master
docker build -t logseq-db-sync .
# pinned
docker build --build-arg LOGSEQ_REF=<sha-or-tag> -t logseq-db-sync .
```

The built commit is stored in `/logseq-sha` inside the image. CI (`build.yml`) pushes to
`ghcr.io/<user>/logseq-db-sync-docker` on push, weekly, or manually with an optional ref.

## Deploy

1. Copy `docker-compose.yml` to the VPS, set `image`, `DB_SYNC_BASE_URL` and the network name
   (`docker network ls`; the one Nginx Proxy Manager uses). Put `DB_SYNC_ADMIN_TOKEN=<random>` in `.env`.
2. `docker compose up -d`
3. In Nginx Proxy Manager add a Proxy Host: domain `sync.example.com`, forward `db-sync` port `8787` (http),
   enable **Websockets Support**, and on the SSL tab request a Let's Encrypt certificate + Force SSL.
4. Back up `./data` (SQLite + assets). Update with `docker compose pull && docker compose up -d`.

If the GHCR package is private, run `docker login ghcr.io` on the VPS with a PAT (`read:packages`).

Auth is Cognito JWT validation (see `deps/db-sync/README.md` upstream).
