#!/usr/bin/env bash
# Restart the probe workers on devloop's current arbor + hearth, re-queueing
# every app that isn't a full menu bar yet (the engine changed since).
set -u
cd "$(dirname "$0")/.."
systemctl --user stop hearth-menu-probe-w0 hearth-menu-probe-w1 hearth-menu-probe-w2 hearth-menu-probe-w3 2>/dev/null
sleep 4
python3 -I - <<'PY'
import glob, json
n = 0
for fn in glob.glob("data/probe*.jsonl"):
    rows = [json.loads(l) for l in open(fn) if l.strip()]
    full = lambda r: r.get("result") == "menus" and len([m for m in r.get("menus", []) if not m.endswith(":0")]) >= 2
    good = {r["attr"] for r in rows if r.get("variant") == "session" and full(r)}
    skip = {r["attr"] for r in rows if r.get("variant") == "build"}
    keep = [r for r in rows if r["attr"] in good or r["attr"] in skip]
    n += len({r["attr"] for r in rows}) - len({r["attr"] for r in keep})
    open(fn, "w").write("".join(json.dumps(r) + "\n" for r in keep))
print(n, "requeued")
PY
for d in "" 1 2 3; do MENU_RIG_DIR=$XDG_RUNTIME_DIR/menu-rig-survey$d ~/.config/Claude/side-session-notes/local_3249e068-f6b4-44ca-966b-72365fe5da97/menu-rig.sh stop 2>/dev/null; done
start() { u=$1; W=$2; shift 2
  for i in $(seq 30); do systemctl --user list-units --all --plain --no-legend "hearth-menu-probe-$u.service" | grep -q . || break; sleep 2; done
  systemd-run --user --quiet --unit=hearth-menu-probe-$u --collect -p Nice=5 -p CPUWeight=50 -p MemoryMax=24G \
    -p StandardOutput=append:$PWD/data/probe$W.log -p StandardError=append:$PWD/data/probe$W.log --working-directory=$PWD \
    -E PATH="$PATH" -E HOME="$HOME" -E XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" -E DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    -E MENU_PROBE_WORKER=$W -E MENU_PROBE_DEVLOOP=1 python3 -I scripts/menu-probe.py --count 5000 --keep-rig "$@"; }
start w0 "" --stride 3 --offset 0; start w1 1 --stride 3 --offset 1; start w2 2 --stride 3 --offset 2
start w3 3 --sources flathub,nixpkgs-uncached
systemctl --user list-units 'hearth-menu-probe-*' --no-pager --plain --no-legend | awk '{print $1,$3,$4}'
