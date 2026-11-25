#!/usr/bin/env bash
# Copy hearth's shared menu components (shared/app-menus/*.qml: MacMenu,
# MacMenuItem, MacMenuSeparator, MacComboBox ..., AppMenu) into Ben's Qt Quick
# apps, so their in-window menus look like hearth's (macOS 26).
# The apps keep vendored copies: they are separate repos and flakes, and a
# copy needs no new flake input or QML import path. These files are the
# canonical ones: change them here, then run this.
#
#   scripts/sync-app-menus.sh            # copy into every app
#   scripts/sync-app-menus.sh --check    # list copies that differ (exit 1 if any)
#   scripts/sync-app-menus.sh APP...     # only these apps (folders under ~/src)
#
# Apps that list their QML files in build.rs also need each file listed
# there; --check reports missing ones.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
src=$here/shared/app-menus
root=${APPS_ROOT:-$HOME/src}
check=0
[[ ${1:-} == --check ]] && { check=1; shift; }
apps=("$@")
[[ ${#apps[@]} -gt 0 ]] || apps=(almanac canopy earshot grove Kog sheaf tessera treetop)
status=0
for app in "${apps[@]}"; do
  dst=$root/$app/qml
  [[ -d $dst ]] || { echo "$app: no qml/ folder" >&2; status=1; continue; }
  for f in "$src"/*.qml; do
    name=$(basename "$f")
    if (( check )); then
      if ! cmp -s "$f" "$dst/$name"; then echo "$app: $name differs"; status=1; fi
    else
      cmp -s "$f" "$dst/$name" || { cp "$f" "$dst/$name"; echo "$app: $name"; }
    fi
    # Explicit build.rs lists (almanac, earshot, Kog, tessera, treetop).
    br=$root/$app/build.rs
    if [[ -f $br ]] && grep -q '"qml/AppMenu.qml"' "$br" && ! grep -q "\"qml/$name\"" "$br"; then
      echo "$app: build.rs doesn't list qml/$name" >&2; status=1
    fi
  done
done
exit $status
