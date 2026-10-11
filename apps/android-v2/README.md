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
