# Jellyfin Soup Auth plugin

Jellyfin **10.11.x** plugin for the Soup entitlement mailbox (Pattern A).

Design: [`docs/ideas/soup-entitlement-mailbox.md`](../../docs/ideas/soup-entitlement-mailbox.md)  
Soup OpenAPI: [`services/soup-identity/openapi/openapi.yaml`](../../services/soup-identity/openapi/openapi.yaml)  
Tailscale mint spike: [`docs/development/tailscale-auth-key-mint-spike-2026-09-10.md`](../../docs/development/tailscale-auth-key-mint-spike-2026-09-10.md)

## Scope

- Plugin config: Soup base URL, plugin Basic credential, server id/audience/issuer
- Seerr bridge (`/SoupSeerr`): Explore tab in Soup clients — browse TMDB through Jellyseerr/Overseerr and request titles as the user's own Seerr account
- Tailscale config: OAuth client (preferred) or API token, tailnet, guest tags, key expiry
- Admin UI: **Dashboard drawer → Soup Invites** (invite/revoke); **Settings** link top-right → connection/Tailscale page
  (Plugins → Settings also opens Invites because jellyfin-web prefers `EnableInMainMenu`; use the in-page Settings link for credentials)
- On invite (email known): mint single-use ephemeral tagged auth key → `POST …/transport-grants` to Soup
- Outbound Soup client: `PUT /v1/servers/{id}`, entitlement upsert/delete, transport-grant deposit
- `POST /SoupAuth/Exchange`: fetch JWKS, verify assertion JWT, map email (`sub`) → Jellyfin user, `AuthenticateDirect`, return `AuthenticationResult`

**Outbound only:** Jellyfin → Soup and Jellyfin → Tailscale. Soup never holds Tailscale owner credentials.

## Build

```bash
export PATH="$HOME/.dotnet:$PATH"   # if using user-local SDK
cd plugins/jellyfin-soup
dotnet build -c Release
```

Copy `Jellyfin.Plugin.Soup/bin/Release/net9.0/Jellyfin.Plugin.Soup.dll` (and IdentityModel deps if not provided by the server) into the Jellyfin plugins folder, or package via `build.yaml`.

## Install from the plugin repository

For Jellyfin 10.11 or 12.2+, published by `task release:publish`:

1. Dashboard → Plugins → Repositories → add
   `https://github.com/jeffreyroulston/soup/releases/latest/download/manifest.json`
2. Dashboard → Plugins → Catalog → **Soup Auth** → Install.
3. Stop and start the Jellyfin process or container. On Jellyfin 12 the Dashboard's
   Restart runs in-process and keeps the old DLL loaded.

## Connect to someone else's Soup Identity

The person who runs Soup Identity issues you a credential with
[`plugin_credentials`](../../services/soup-identity/README.md#plugin-credentials-other-peoples-servers).
After [installing the plugin](#install-from-the-plugin-repository):

1. Dashboard drawer → **Soup Invites** → top right **Settings**.
2. Enter the settings they sent you. Keep each value exactly as sent.
3. Set **Jellyfin base URL** to the address your TV can reach, such as
   `http://192.168.1.50:8096`.
4. Leave the Tailscale fields blank if guests watch on LG TVs: the webOS app can't
   use Tailscale, so it connects to the base URL directly.
5. Save → top right **Invites** → **Register server**, then invite each person by
   Google email.

## Local Jellyfin Docker (plugin baked in)

```bash
cd plugins/jellyfin-soup
./scripts/stage-plugin.sh          # publish DLL + IdentityModel + meta.json → docker/plugin/
docker compose -f docker/docker-compose.yml up --build
```

Or from the repo root: `task jellyfin:up`.

- UI: http://localhost:8096 (complete the first-run wizard)
- Soup Identity (if running): use Soup base URL `http://host.docker.internal:8787`
- Plugin id/secret must match Soup `BOOTSTRAP_PLUGIN_*` (`dev-plugin` / `dev-plugin-secret-change-me`)

Rebuild after plugin changes:

```bash
task jellyfin:rebuild
```

## Configure

1. Dashboard drawer → **Soup Invites** (or Plugins → Soup Auth → Settings — same invites page)
2. Top right → **Settings** → set Soup base URL (e.g. `http://host.docker.internal:8787`)
3. Set plugin id/secret to match Soup `BOOTSTRAP_PLUGIN_*`
4. Set `ServerId` + `Audience` (JWT `aud`, e.g. `jellyfin:home-jf`)
5. Set `AssertionIssuer` to Soup `ASSERTION_ISSUER` (default `https://soup.local/identity`)
6. **Tailscale (optional but required for guest transport):**
   - Prefer OAuth client with `auth_keys` scope, bound to `tag:soup-guest`
   - Or paste a user API token (`tskey-api-…`) as fallback
   - Set guest tags (default `tag:soup-guest`) and expiry (default 1800s)
7. Save → top right **Invites** (or drawer) → **Register server** → invite by **Google email**

Guest sign-in uses Soup Identity device-link (QR + TV code → Google → optional enter-code form). See [`services/soup-identity/README.md`](../../services/soup-identity/README.md#google-oidc-setup).

Direct URLs:
- Invites: `http://localhost:8096/web/#/configurationpage?name=SoupInvites`
- Settings: `http://localhost:8096/web/#/configurationpage?name=Soup%20Auth`

After plugin code changes: `task jellyfin:rebuild`.

### Owner ACL sketch

Tag the Jellyfin host `tag:soup-jellyfin` and allow guests only to Jellyfin ports. See the Wave 1C spike for the full `tagOwners` / `grants` snippet.

## Invite → mint → deposit

When `MintTailscaleAuthKeyOnInvite` is on and Tailscale credentials are set:

1. Upsert entitlement on Soup
2. `POST https://api.tailscale.com/api/v2/oauth/token` (if OAuth) then `POST …/tailnet/{tailnet}/keys`
   - `reusable=false`, `ephemeral=true`, `preauthorized=true`, tags from config
3. `POST /v1/servers/{serverId}/entitlements/{email}/transport-grants` with:
   - `grant_type=tailscale_auth_key`
   - `material` = one-time `tskey-auth-…`
   - `ttl_seconds` = `min(1800, expirySeconds - 60)` (Soup expires first)
   - `tailscale_key_id` + capability echo for audit
4. Store `TailscaleKeyId` on the local entitlement row (for revoke)

Re-inviting the same email does **not** remint if a key id is already stored. Use **Remint** (`POST …/TransportGrant`) to force a new key (revokes the previous unused key first). Sync entitlements upserts Soup rows only — no remint.

If deposit to Soup fails after mint, the plugin DELETE-revokes the freshly minted Tailscale key so unused secrets do not linger.

## Revoke / cleanup behavior

| Event | Plugin action | Tailscale | Soup |
| --- | --- | --- | --- |
| Owner clicks **Revoke** | Mark local row `Revoked`, clear stored key id | `DELETE …/keys/{TailscaleKeyId}` when known (best-effort; 404 OK) | `DELETE …/entitlements/{email}` (Wave 4: atomic grant soft-revoke + entitlement delete) |
| Unused key past Tailscale `expirySeconds` | None required | Key auto-expires | Grant `expires_at` makes claim impossible |
| Unused grant past Soup TTL | None required | Key may still exist until expiry/DELETE | Unclaimable |
| Deposit fails after mint | Surface invite/remint error | Immediate DELETE of minted key | No grant stored |
| Guest goes offline (ephemeral node) | Entitlement can remain | Node auto-removed by Tailscale | New grant needed for re-join → use **Remint** |
| Sync entitlements | Upsert only | No mint/revoke | Entitlement rows refreshed |

Wave 4 acceptance (TTL + DELETE + secret-safe logs + TV ~60s):
[`docs/development/android-soup-hardening-wave4-2026-09-10.md`](../../docs/development/android-soup-hardening-wave4-2026-09-10.md).
v1 does not call Tailscale `devices:core` for node purge.


## Seerr (Explore tab)

Point the plugin at a Jellyseerr/Overseerr server and Soup clients grow an **Explore** tab: search TMDB,
browse trending/popular/upcoming, see what's already in the library, and request what isn't.

Setup (Plugins → Soup Auth → Settings → *Seerr*):

1. **Seerr URL** as reachable from the Jellyfin host, e.g. `http://jellyseerr:5055`
2. **Seerr API key** from Seerr → Settings → General
3. **Test Seerr connection**, then Save

How users are matched: every call carries the caller's Jellyfin session. The plugin looks the user up in
Seerr by Jellyfin user id (`GET /api/v1/user/jellyfin/{id}`, falling back to a scan of `/api/v1/user` on
older servers) and sends requests with `userId` set to that account, so Seerr's own permissions, quotas
and auto-approval apply. A user with no Seerr account can browse but not request; they need to sign in
to Seerr with Jellyfin once. The API key never leaves the Jellyfin host and only allow-listed catalogue
paths are proxied.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/SoupSeerr/Status` | `{configured, reachable, version, user}` — clients show the tab when `configured` |
| GET | `/SoupSeerr/Browse/{path}` | Proxy for `search`, `discover/…`, `movie/…`, `tv/…`, `person/…`, `collection/…`, `genres/…` (query string forwarded) |
| GET | `/SoupSeerr/Requests?filter=&take=&skip=` | The caller's own requests |
| POST | `/SoupSeerr/Request` | `{mediaType, mediaId, tvdbId?, seasons?, is4k?}` as the caller's Seerr user |
| DELETE | `/SoupSeerr/Request/{id}` | Withdraw the caller's own pending request (request managers: any) |
| POST | `/SoupSeerr/Test` | Admin: try a URL/key before saving |

Matched user lookups are cached for 10 minutes (1 minute for misses); Save + Test clears the cache.

## Exchange

```http
POST /SoupAuth/Exchange
Content-Type: application/json

{
  "assertion": "<jwt from Soup POST /v1/assertions>",
  "deviceId": "...",
  "deviceName": "...",
  "app": "Soup",
  "appVersion": "0.1.0"
}
```

Returns a normal Jellyfin `AuthenticationResult` (`AccessToken`, `User`, `SessionInfo`, …).

## Admin API (elevation required)

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/SoupAuth/Entitlements` | List Pending/Active |
| POST | `/SoupAuth/Entitlements/Invite` | Invite by `email`; mint+deposit when configured |
| POST | `/SoupAuth/Entitlements/{idOrEmail}/TransportGrant` | Force remint + deposit |
| DELETE | `/SoupAuth/Entitlements/{idOrEmail}` | Revoke locally + Tailscale key DELETE + Soup DELETE |
| POST | `/SoupAuth/RegisterServer` | Soup `PUT /v1/servers/{serverId}` |
| POST | `/SoupAuth/Sync` | Register + upsert all Active rows (no remint) |
