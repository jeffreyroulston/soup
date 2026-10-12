# Soup identity — fill line

The lowercase Manrope ExtraBold `soup` wordmark from the web app, with the `o`
filled to the line in the accent orange: a bowl, seen side on. The icon is the same
idea as a ring on the web canvas gradient.

| Token  | Value                          |
| ------ | ------------------------------ |
| Ink    | `#F5F5F7` (light: `#1D1D1F`)   |
| Accent | `#FC7814` (light: `#E86A0C`)   |
| Canvas | `#1C1C1E` → `#050506` gradient |

## Masters

- `soup-wordmark.svg`, `soup-wordmark-light.svg`: outlined wordmark for dark and light grounds.
- `soup-mark.svg`, `soup-mark-light.svg`: the ring on its own, transparent.
- `soup-icon.svg`: full-bleed square for platforms that apply their own mask.
- `soup-icon-rounded.svg`: pre-rounded tile (favicon, Flutter `SoupMark`, legacy launchers).
- `android-foreground.svg`: adaptive-icon foreground, drawn with a 22dp inset.
- `android-tv-banner.svg`: 320×180dp leanback banner.

## Where they're used

- Web: `SoupWordmark.vue` (nav, login); `public/` favicon, touch icon, PWA icons and manifest.
- android-v2: `SoupWordmark` widget (nav, login, status, touch app bar), adaptive launcher,
  splash, TV banner.
- android: adaptive launcher, TV banner and `SoupMark`. The festival onboarding type is unchanged.

## Regenerating

`generate.py` draws everything from the Manrope outlines. The wordmark is drawn as paths,
so it renders the same everywhere.

```sh
python3 -c "from fontTools.ttLib import TTFont; from fontTools.varLib.instancer import instantiateVariableFont as i; i(TTFont('apps/android-v2/assets/fonts/Manrope-Variable.ttf'), {'wght': 800}).save('/tmp/Manrope-800.ttf')"
python3 docs/branding/generate.py <out-dir> /tmp/Manrope-800.ttf
```

The script writes `wordmark.json` and `wordmark_paths.dart.txt` for updating the Vue
and Flutter components. Rasters come from the SVGs via `rsvg-convert`.
