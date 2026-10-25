# logseq-db-sync-docker

Docker image of the self-hosted Node adapter in [`logseq/logseq`](https://github.com/logseq/logseq/tree/master/deps/db-sync).
The image build clones Logseq and compiles the adapter. It supports `linux/amd64` and `linux/arm64`.

## What this does (and does not do)

This runs the db-sync API and stores graph metadata, graph data, and assets on your server. It does **not**
run Logseq's user-account or identity service. The adapter validates Logseq login tokens issued by the
configured Amazon Cognito user pool. Therefore, users still sign in to Logseq with their Logseq account;
the custom URL changes where sync requests go, not how users authenticate. The Cognito values in the
provided Compose file are Logseq's published values.

`DB_SYNC_ADMIN_TOKEN` is an optional, privileged server-side token for administrative operations and
access checks. Keep it secret, do not enter it in Logseq, and do not put it in a public file or URL.

## Requirements

- A Linux VPS with Docker Engine and the Docker Compose plugin.
- A DNS name (for example, `sync.example.com`) pointing to the VPS.
- Nginx Proxy Manager (NPM), with ports 80 and 443 reachable from the internet.
- The db-sync container and NPM attached to the same Docker network.

## Deploy on a VPS

### 1. Create the deployment directory and download Compose

```bash
sudo mkdir -p /opt/db-sync/data
sudo chown -R 1000:1000 /opt/db-sync/data
sudo chown "$USER":"$USER" /opt/db-sync
cd /opt/db-sync
wget https://raw.githubusercontent.com/Jarf10/logseq-db-sync-docker/main/docker-compose.yml
```

The container runs as the unprivileged `node` user (UID/GID 1000). The ownership command allows it to
create its SQLite database and asset files in the bind-mounted `data` directory. If you already started
the container and it failed with `SQLITE_CANTOPEN`, stop it and run the `chown` command above before
starting it again.

### 2. Set the image, public URL, and NPM network

Edit the file:

```bash
nano docker-compose.yml
```

Set these values:

- **`image`**: `ghcr.io/jarf10/logseq-db-sync-docker:latest`
- **`DB_SYNC_BASE_URL`**: your final HTTPS URL, such as `https://sync.example.com`. Do not append `/sync` or `/health`.
- **`networks.npm.name`**: the Docker network NPM uses. Find network names with `docker network ls`.
  To see which one is attached to NPM, run `docker inspect <npm-container-name> --format '{{json .NetworkSettings.Networks}}'`.
  Use the network name shown there; it may not be `nginx-proxy-manager_default`.

Keep the three `COGNITO_*` values as provided unless you have a separately configured Cognito user pool,
client, and matching JWT issuer. The Docker image does not create those identity resources.

Create a private admin token in the Compose directory:

```bash
umask 077
printf 'DB_SYNC_ADMIN_TOKEN=%s\n' "$(openssl rand -hex 32)" > .env
```

The compose file publishes no host port: NPM reaches the service internally over the shared Docker
network. Do not expose port 8787 directly to the public internet.

### 3. Start the service

The GHCR package is publicly pullable, so no registry login is needed unless the package is made private.

```bash
docker compose pull
docker compose up -d
docker compose logs -f db-sync
```

The startup log should include `Logseq sync listening on port 8787`. If it exits, inspect the logs. For
`SQLITE_CANTOPEN`, verify `/opt/db-sync/data` is owned by UID/GID 1000.

### 4. Configure Nginx Proxy Manager

Create a DNS **A** record for the chosen hostname pointing to your VPS public IP. Then in NPM, add a
Proxy Host:

- **Domain Names**: your hostname, for example `sync.example.com`
- **Scheme**: `http`
- **Forward Hostname / IP**: `db-sync` (the Compose service name)
- **Forward Port**: `8787`
- Enable **Websockets Support**
- On the **SSL** tab, request a Let's Encrypt certificate, enable **Force SSL**, and save

The DNS record must resolve to the VPS and ports 80/443 must be reachable for Let's Encrypt validation.
The NPM container must be connected to the same Docker network specified in Compose.

### 5. Validate the endpoint

From the VPS or another machine:

```bash
curl -fsS https://sync.example.com/health
```

Expected response:

```json
{"ok":true}
```

If this returns `502 Bad Gateway`, check that both containers share the configured Docker network and
that the NPM forward hostname and port are `db-sync:8787`. If the container exits with a database error,
check the data-directory ownership and `docker compose logs db-sync`.

### 6. Point Logseq at this server and sign in

In Logseq, open **Settings → Sync → Sync server URL**, enter the base URL such as
`https://sync.example.com` (without `/sync` or `/health`), and save it. Then log in to Logseq with your
Logseq account and enable Sync for the database graph. Set the URL separately on each device/profile.

The sign-in is still required because Logseq uses the account to obtain Cognito-issued tokens that identify
the user and authorize access to their graph. The custom sync URL only redirects sync API and WebSocket
traffic to your VPS; it does not replace the account login or provide a new self-hosted identity provider.
The server checks those tokens using the Cognito issuer and JWKS URL. `DB_SYNC_ADMIN_TOKEN` is not a
replacement for a user login and must never be entered in the app.

## Updates and backups

Back up `/opt/db-sync/data` regularly; it contains the SQLite database and filesystem assets. To update
to the latest image:

```bash
cd /opt/db-sync
docker compose pull
docker compose up -d
```

The GitHub Actions workflow publishes `latest` on a push to `main`, weekly, and when manually dispatched.
By default it builds the latest Logseq `master`; a workflow dispatch can specify a commit SHA, tag, or
branch to build a particular source revision.

## Build locally

From a clone of this repository:

```bash
# Latest Logseq master
docker build -t logseq-db-sync .

# Specific Logseq commit SHA, tag, or branch
docker build --build-arg LOGSEQ_REF=<sha-or-tag> -t logseq-db-sync .
```

The Logseq source revision used for the build is stored at `/logseq-sha` inside the image.
