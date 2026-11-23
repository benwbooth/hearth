#!/usr/bin/env bash
# Free the disk the survey used: run every ~15 min while probing (systemd
# timer hearth-menu-janitor) and once at the end (cleanup-all.sh).
#  - Nix: paths in the closures of the apps tested so far that are dead now
#    (nothing references them: not the system, not a running app, not the
#    tools' roots). `nix store delete` of a chosen set needs a newer daemon,
#    and `nix-store --delete` aborts on the first live path, so: dead list
#    ∩ our closures, deleted in one call; a path that came alive meanwhile
#    is dropped with its closure and the call repeated.
#  - Flatpak: the throwaway installation's apps not running in a sandbox
#    right now, then unused runtimes.
set -u
cd "$(dirname "$0")/.."
log() { echo "$(date +%T) $*"; }
python3 -I - <<'PY'
import json, glob, os, re, subprocess, time
def run(args):
    return subprocess.run(args, capture_output=True, text=True)
stores = set()
for fn in glob.glob("data/probe*.jsonl"):
    for l in open(fn):
        try:
            s = json.loads(l).get("store")
        except ValueError:
            continue
        if s and os.path.exists(s):
            stores.add(s)
if stores:
    ours = set(run(["nix-store", "-qR", *sorted(stores)]).stdout.split())
    dead = set(run(["nix-store", "--gc", "--print-dead"]).stdout.split())
    todo = ours & dead
    print(time.strftime("%T"), f"nix: {len(todo)} dead paths from tested apps", flush=True)
    freed, rounds = 0.0, 0
    # One call for the whole set. A path that came alive meanwhile (a
    # worker's new app shares a library) makes nix refuse all of it: drop
    # that path with its closure and try again.
    while todo and rounds < 60:
        rounds += 1
        r = run(["nix-store", "--delete", *sorted(todo)])
        m = re.search(r"Cannot delete path '([^']+)'", r.stderr)
        d = re.search(r"(\d+) store paths deleted, ([\d.]+) (\w+) freed", r.stdout + r.stderr)
        if d:
            freed += float(d.group(2)) * {"KiB": 1 / 1024 ** 2, "MiB": 1 / 1024, "GiB": 1}.get(d.group(3), 0)
        if not m:
            break
        alive = set(run(["nix-store", "-qR", m.group(1)]).stdout.split()) | {m.group(1)}
        todo -= alive
    print(time.strftime("%T"), f"nix: freed {freed:.1f} GiB in {rounds} rounds", flush=True)
PY
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
