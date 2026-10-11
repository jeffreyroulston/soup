# Soup Web

Nuxt 4 SPA, built as static files so one central deployment serves everyone. Sign-in runs entirely in the browser: it talks to **Soup Identity** for device-link and tokens, then exchanges an assertion **directly with the user's Jellyfin** (`/SoupAuth/Exchange`) for browse and playback. There is no app server.

### Where the login lives

| Key | Storage | Holds |
| --- | --- | --- |
| `soup.identity.tokens` | localStorage | Soup access + refresh token, email, expiry (shared by all tabs; refreshed under a Web Lock because Identity rotates refresh tokens). XSS on this origin can steal the session — residual risk without a BFF. |
| `soup.jellyfin.session` | sessionStorage | This tab's Jellyfin token, so a reload skips the exchange |
| `soup.jellyfin.direct` | localStorage | Direct Jellyfin username/password sign-in |
| `soup.jellyfin.deviceId` | localStorage | One Jellyfin device ID per browser |
| `soup.server.preferred` | localStorage | Roster id of the server to sign in to. With several servers and none saved, sign-in shows a picker; Settings switches between them |

A Jellyfin 401 re-runs the exchange from the stored Soup tokens; a rejected refresh token signs the browser out.

## Mock mode (UI without backends)

No Identity or Jellyfin required. Serves an in-memory catalog with SVG posters and a public sample video.

```sh
NUXT_PUBLIC_MOCK=true task web:dev
```

Open `http://localhost:3000` — you are signed in as `mock@soup.dev` automatically. Logout returns to a mock login screen; **Enter mock library** signs back in.

## Prerequisites (live mode)

1. **Soup Identity** reachable from users' browsers at `NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL` (default `https://soup-idm.bestiestudios.com`) — see [`services/soup-identity/README.md`](../../services/soup-identity/README.md). Identity already serves open CORS. Its `PUBLIC_BASE_URL` (the verification page) must be reachable too.
2. Jellyfin with the Soup plugin, and the user's Google/dev email **entitled** on the roster with a `base_url` / `magic_dns` **their browser** can reach (LAN or Tailscale).
3. **Jellyfin CORS** allows the web app's origin (`http://localhost:3000` in dev, the hosted origin in production).
4. **HTTPS:** an https-hosted app can't call an `http://` Jellyfin (mixed content). On https pages the exchange prefers the server's `magic_dns` (`https://…ts.net`), so give servers a Tailscale name or put them behind TLS.

### Jellyfin CORS (operator-owned)

In Jellyfin Dashboard → Networking (wording varies by version), allow the app origin, e.g.:

```text
http://localhost:3000
https://soup.example.com
```

## Develop

```sh
cp apps/web/.env.example apps/web/.env
task web:deps
task web:dev
```

Open `http://localhost:3000`. Sign in starts Identity device-link (Google or `ALLOW_DEV_LOGIN` verification page). DevTools Network shows only Identity and Jellyfin origins.

**Playback:** Item detail → Play / Resume → `/watch/:id`. Direct play uses `api_key` on the stream URL; HLS falls back via `hls.js`. Progress posts to Jellyfin `Sessions/Playing*`.

## Central hosting

```sh
NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL=https://identity.example.com task web:generate
task web:preview   # optional local check on :3001
```

Deploy `apps/web/.output/public` to any static host (Cloudflare Pages, Netlify, nginx, S3 + CDN). `NUXT_PUBLIC_*` values are baked in at build time as defaults.

### Runtime config (no rebuild)

The app fetches `soup.config.json` from its base path on startup. Edit that file in the deployed folder to repoint a deployment:

```json
{ "soupIdentityBaseUrl": "https://identity.example.com", "jellyfinUrl": "", "appName": "Soup" }
```

Precedence for the Identity URL: Settings → Identity server (saved in that browser) → `soup.config.json` → build-time env. `task web:generate:nas` copies `deploy/nas/soup.config.json` into the build.

The host must fall back to the SPA shell for unknown paths so deep links like `/item/:id` load: serve `200.html` (or `index.html`) for any path that isn't a file. nginx:

```nginx
location / { try_files $uri $uri/ /200.html; }
```

## Env

| Variable | Purpose |
| --- | --- |
| `NUXT_PUBLIC_MOCK` | `true` = in-memory catalog, skip Identity/Jellyfin |
| `NUXT_PUBLIC_SOUP_IDENTITY_BASE_URL` | Identity base URL the browser calls |
| `NUXT_PUBLIC_APP_ORIGIN` | Documented app origin for CORS |
| `NUXT_PUBLIC_APP_NAME` | UI title |
