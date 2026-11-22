#!/usr/bin/env bash
# Friends release: a GitHub release with the webOS IPK and the Soup Auth plugin
# and its Jellyfin repository manifest. Friends run the TV installer from a clone
# of this repo; it downloads the IPK from the latest release.
#
#   release.sh build     Build everything into dist/release/
#   release.sh publish   Upload dist/release/ as a GitHub release
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/dist/release"
REPO=jeffreyroulston/soup
PLUGIN_DIR="$ROOT/plugins/jellyfin-soup"
APPINFO="$ROOT/apps/android-v2/webos/meta/appinfo.json"

DOTNET="${DOTNET:-$HOME/.dotnet/dotnet}"
[[ -x "$DOTNET" ]] || DOTNET="$(command -v dotnet)"

version="$(node -p "require('$APPINFO').version")"
app_id="$(node -p "require('$APPINFO').id")"
tag="v$version"

# Jellyfin picks the highest version whose targetAbi is <= the server's, so the
# last segment keeps the 12.x build ahead of the 10.11 one on a 12.x server.
plugin_base="$(sed -n 's:.*<Version>\([0-9]*\.[0-9]*\.[0-9]*\)\..*</Version>.*:\1:p' "$PLUGIN_DIR/Directory.Build.props")"

build_plugin() { # <jellyfin-version> <target-abi> <version-suffix>
  local jellyfin="$1" abi="$2" plugin_version="$plugin_base.$3"
  local stage zip_name="soup-auth-jellyfin-${jellyfin%.*}.zip"
  stage="$(mktemp -d)"
  "$DOTNET" publish "$PLUGIN_DIR/Jellyfin.Plugin.Soup/Jellyfin.Plugin.Soup.csproj" \
    -c Release -o "$stage/publish" --nologo -v quiet \
    -p:JellyfinVersion="$jellyfin" -p:Version="$plugin_version" \
    -p:AssemblyVersion="$plugin_version" -p:FileVersion="$plugin_version"
  node "$ROOT/tool/release/plugin-meta.mjs" "$plugin_version" "$abi" >"$stage/meta.json"
  # Only the plugin and the IdentityModel deps Jellyfin doesn't provide.
  python3 -m zipfile -c "$OUT/$zip_name" "$stage/meta.json" \
    "$stage/publish/Jellyfin.Plugin.Soup.dll" "$stage"/publish/Microsoft.IdentityModel.*.dll
  rm -rf "$stage"
  printf '%s %s %s %s\n' "$plugin_version" "$abi" "$zip_name" "$(md5sum "$OUT/$zip_name" | cut -d' ' -f1)" >>"$OUT/.plugins"
}

build() {
  # The installer launches the app by this id, so the two must not drift.
  grep -qF "APP_ID = '$app_id'" "$ROOT/tool/soup-install/soup-install.mjs" \
    || { echo "APP_ID in soup-install.mjs doesn't match $app_id" >&2; exit 1; }

  rm -rf "$OUT"
  mkdir -p "$OUT"

  (cd "$ROOT" && task v2:webos:build)
  cp "$ROOT/apps/android-v2/build/webos/arm/release/ipk/${app_id}_${version}_arm.ipk" \
    "$OUT/soup-webos-arm.ipk"

  build_plugin 10.11.5 10.11.0.0 11
  build_plugin 12.2.0 12.2.0.0 12
  node "$ROOT/tool/release/plugin-manifest.mjs" "$REPO" "$tag" "$OUT/.plugins" >"$OUT/manifest.json"
  rm "$OUT/.plugins"

  (cd "$OUT" && sha256sum -- * >SHA256SUMS)
  git -C "$ROOT" rev-parse HEAD >"$OUT/.commit"
  git -C "$ROOT" status --porcelain >"$OUT/.dirty"

  echo "Built $tag from $(cut -c1-7 "$OUT/.commit") → dist/release/"
  [[ -s "$OUT/.dirty" ]] && echo "Note: the working tree has uncommitted changes, so this build can't be published."
  ls -la "$OUT"
}

publish() {
  [[ -f "$OUT/.commit" ]] || { echo "Nothing built. Run: task release:build" >&2; exit 1; }
  [[ -s "$OUT/.dirty" ]] && { echo "This build included uncommitted changes. Commit, then rebuild." >&2; exit 1; }
  local commit
  commit="$(cat "$OUT/.commit")"
  [[ "$commit" == "$(git -C "$ROOT" rev-parse HEAD)" ]] \
    || { echo "HEAD has moved since this build. Rebuild first." >&2; exit 1; }
  if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
    echo "$tag already exists. Bump version in $APPINFO, then rebuild." >&2
    exit 1
  fi
  gh release create "$tag" --repo "$REPO" --target "$commit" --title "Soup $version" \
    --notes "Install on an LG TV: see tool/soup-install/README.md" \
    "$OUT"/soup-webos-arm.ipk "$OUT"/soup-auth-*.zip "$OUT"/manifest.json "$OUT"/SHA256SUMS
}

case "${1:-}" in
  build) build ;;
  publish) publish ;;
  *) sed -n 2,6p "${BASH_SOURCE[0]}"; exit 1 ;;
esac
