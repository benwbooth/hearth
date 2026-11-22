#!/usr/bin/env bash
# Free the disk the survey used: run every ~15 min while probing (systemd
# timer hearth-menu-janitor) and once at the end (cleanup-all.sh).
#  - Nix: paths in the closures of the apps tested so far that are dead now
#    (nothing references them: not the system, not a running app, not the
#    tools' roots). `nix store delete` of a chosen set needs a newer daemon,
#    and `nix-store --delete` aborts on the first live path, so: dead list
#    ∩ our closures, deleted in batches (a batch that turned live is
#    skipped until next time).
#  - Flatpak: the throwaway installation's apps not running in a sandbox
#    right now, then unused runtimes.
set -u
cd "$(dirname "$0")/.."
log() { echo "$(date +%T) $*"; }
stores=$(cat data/probe*.jsonl 2>/dev/null | jq -r 'select(.store != null) | .store' | sort -u | while read -r p; do [ -e "$p" ] && echo "$p"; done)
if [ -n "$stores" ]; then
  closure=$(echo "$stores" | xargs -r nix-store -qR 2>/dev/null | sort -u)
  dead=$(nix-store --gc --print-dead 2>/dev/null | sort -u)
  del=$(comm -12 <(echo "$closure") <(echo "$dead"))
  n=$(echo "$del" | grep -c . || true)
  log "nix: $n dead paths from tested apps"
  [ "$n" -gt 0 ] && echo "$del" | xargs -r -n 200 nix-store --delete 2>&1 | grep -E "store paths deleted" | awk '{d+=$1} END {print "  deleted", d+0}'
fi
export FLATPAK_USER_DIR=$HOME/.cache/hearth-menu-survey/flatpak
if [ -d "$FLATPAK_USER_DIR" ]; then
  running=$(grep -h '^name=' /proc/[0-9]*/root/.flatpak-info 2>/dev/null | cut -d= -f2 | sort -u)
  for app in $(flatpak --user list --app --columns=application 2>/dev/null); do
    grep -qx "$app" <<<"$running" && continue
    flatpak --user uninstall -y --noninteractive "$app" >/dev/null 2>&1 && log "flatpak: removed $app"
  done
  flatpak --user uninstall -y --noninteractive --unused >/dev/null 2>&1
  log "flatpak: $(du -sh "$FLATPAK_USER_DIR" | cut -f1) left"
fi
log "free: $(df -h /nix | awk 'NR==2 {print $4}')"
