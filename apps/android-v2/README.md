# Soup v2 (Android TV)

Flutter TV client whose UI mirrors the web app (`apps/web`), on top of the same
embedded-Tailscale transport and Soup Identity sign-in as `apps/android`.

## Layout

- `packages/soup_core` — shared non-UI code (Jellyfin API wrapper, Tailscale and
  identity view models, caches, playback bridge). Imported via
  `package:soup_core/soup_core.dart`.
- `lib/src/data` — `Catalog` (everything the UI reads/writes), the live
  `JellyfinCatalog` (port of `useJellyfin.ts`), `MockCatalog`, domain models,
  curated packs. `curated_packs.g.dart` is generated from the web app:
  `node tool/gen_curated_packs.mjs`.
- `lib/src/ui` — design tokens (ported from `main.css`), `Glass`, `Focusable`
  (the D-pad focus ring), cards, rows, hero, nav.
- `lib/src/features` — home, item, library, search, collection, settings,
  playback, auth (Soup device-link + direct Jellyfin login).

The app is laid out on a fixed 1440×810 canvas (`DesignScale`) so every TV looks
like the web design regardless of pixel ratio.

## Running

```sh
task v2:run DEVICE=emulator-5554                       # real sign-in
task v2:run DEVICE=emulator-5554 -- --dart-define=SOUP_MOCK=true   # offline mock library
task test:v2
```

Soup Identity defaults to `https://soup-idm.bestiestudios.com`; override with
`--dart-define=SOUP_IDENTITY_BASE_URL=http://10.0.2.2:8787`.

The emulator clock must be correct or TLS to the identity server fails
(`certificate is not yet valid`); cold-boot with
`task emulator:tv:start -- -no-snapshot-load` if it has drifted.

## webOS

The same app builds for LG webOS TVs through LG's
[flutter-webOS](https://github.com/lg-flutter-webos/flutter-webos) (webOS TV 26
Re:New and later). The webOS project lives in `webos/`; `webos/meta/appinfo.json`
holds the app id, title and icons.

What differs on webOS (`lib/src/platform.dart`):

- Always the TV layout.
- No embedded Tailscale (libtailscale is only built for Android), so sign-in
  connects directly to Jellyfin and the Tailscale options are hidden.
- The window claims the remote's Back key (`_WEBOS_ACCESS_POLICY_KEYS_BACK`;
  otherwise webOS closes the app), and it is replayed as Android's system back.
- Video plays on a hardware plane beneath Flutter (`"transparent": true` in
  `appinfo.json`), so the player and `DesignScale` stay see-through there.
- Plugins come from LG's `*_webos` packages in `pubspec.yaml`.

flutter-webOS pins Flutter 3.38 (Dart 3.10), so the Dart packages here must keep
`sdk: ^3.10.0` and avoid newer language features.

Builds run in an Ubuntu container (`tool/webos/Dockerfile`, trimmed from LG's
[devcontainer](https://github.com/lg-flutter-webos/devcontainer)), so only
Docker is needed on the host. The container keeps its own `.dart_tool`, pub
cache and lockfile (`webos/pubspec.lock`), so the Android setup is untouched.

The image installs LG's webOS NDK, which is under LG's SDK License Agreement
([summary](https://github.com/lg-flutter-webos/devcontainer#webos-ndk-license)).
The build stops until you accept it by setting `WEBOS_NDK_ACCEPT_EULA=1` for
the first image build:

```sh
WEBOS_NDK_ACCEPT_EULA=1 task v2:webos:build   # first time: builds the image too
task v2:webos:build                           # → build/webos/arm/release/ipk/*.ipk
task v2:webos:shell                           # flutter-webos devices / run on a TV
```

### Deploying to a TV

1. On the TV, install LG's **Developer Mode** app from the LG Content Store,
   sign in with an LG developer account, turn on Dev Mode Status (the TV
   restarts), then turn on **Key Server**. Note the TV's IP and the passphrase.
2. Register the TV once (the registration and SSH key persist in Docker
   volumes):

   ```sh
   task v2:webos:shell
   flutter-webos custom-devices add            # id e.g. livingroom, TV IP, port 9922
   flutter-webos custom-devices get-key -d livingroom   # enter the passphrase
   flutter-webos devices                       # should list the TV
   ```

3. Build, install and launch: `task v2:webos:run DEVICE=livingroom`
   (`MODE=debug` for hot reload; `q` quits and closes the app on the TV).

Dev Mode expires after a while; extend it in the Developer Mode app.
