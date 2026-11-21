#!/usr/bin/env bash
# Rebuild hearth's built-in user pictures (avatars/: PNGs, index.json,
# CREDITS.md) from scripts/avatars/manifest.tsv. The results are committed,
# so the hearth package never downloads anything; run this only to change
# the set. Sources are pinned (Fluent Emoji by commit, Commons by page id)
# and cached in ~/.cache/hearth-avatar-build.
#   scripts/build-avatars.sh            # everything
#   scripts/build-avatars.sh fox,lake   # just these ids
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
if [[ -z ${HEARTH_AVATAR_TOOLS:-} ]]; then
  export HEARTH_AVATAR_TOOLS=1
  # hearth's own locked nixpkgs (flake.lock), so the tools match every time.
  exec nix shell --impure --expr "with (builtins.getFlake \"git+file://$repo\").inputs.nixpkgs.legacyPackages.x86_64-linux; [ (python3.withPackages (p: [ p.pillow ])) pngquant oxipng ]" \
    -c "$0" "$@"
fi
cache=${XDG_CACHE_HOME:-$HOME/.cache}/hearth-avatar-build
args=(--manifest "$repo/scripts/avatars/manifest.tsv" --out "$repo/avatars" --cache "$cache")
[[ -n ${1:-} ]] && args+=(--only "$1")
python3 -I "$repo/scripts/avatars/build.py" "${args[@]}"
du -sh "$repo/avatars"
