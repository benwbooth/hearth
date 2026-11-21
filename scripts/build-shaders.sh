#!/usr/bin/env bash
# Compile shell/shaders/*.frag into the .qsb files Qt Quick loads (the .qsb
# files are committed, so running the shell needs no shader tools).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
qsb=$(nix build --no-link --print-out-paths --inputs-from /etc/nixos nixpkgs#qt6.qtshadertools | tail -1)/bin/qsb
for f in "$repo"/shell/shaders/*.frag; do
  "$qsb" --qt6 -o "$f.qsb" "$f"
  echo "built ${f#$repo/}.qsb"
done
