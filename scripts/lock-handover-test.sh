#!/usr/bin/env bash
# Lock handover test: an older hearth holds the session lock while a newer
# one starts (as when devloop swaps shells under a locked screen). The new
# one's lock is refused while the old client lives; once the old one dies,
# the new one must end up holding the lock (Lock.qml retries).
# 2026-11-21: the new hearth gave up after 4 s and arbor stayed locked with
# no lock client and nothing to type into.
#
#   scripts/lock-handover-test.sh [--hearth BIN] [--arbor BIN] [--term] [--keep] [--delay S]
#
# BIN defaults to this checkout's package (nix build .#hearth) and devloop's
# arbor. --term stops the old shell with TERM through its wrapper (as devloop
# does) instead of killing quickshell outright. --delay: seconds A lives on
# after B's first refusal (default 1). Runs entirely nested: virtual
# KWin, nested arbor, private XDG_RUNTIME_DIR, HOME and session bus.
set -uo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
state_root=${XDG_STATE_HOME:-$HOME/.local/state}
arbor_bin="" hearth_bin="" term=0 keep=0 delay=1
while (($#)); do
  case $1 in
    --arbor) arbor_bin=$2; shift 2 ;;
    --hearth) hearth_bin=$2; shift 2 ;;
    --term) term=1; shift ;;
    --keep) keep=1; shift ;;
    --delay) delay=$2; shift 2 ;;
    *) echo "usage: $0 [--hearth BIN] [--arbor BIN] [--term] [--keep] [--delay S]" >&2; exit 2 ;;
  esac
done
if [[ -z $arbor_bin ]]; then
  arbor_bin=$state_root/devloop/arbor/bin/arbor
  [[ -x $arbor_bin ]] || arbor_bin=$(command -v arbor) || { echo "no arbor" >&2; exit 2; }
fi
[[ -n $hearth_bin ]] || hearth_bin=$(nix build --no-link --print-out-paths "$repo#hearth" | tail -1)/bin/hearth
hearth_bin=$(readlink -f "$hearth_bin")
qs=$(grep -ho '/nix/store/[^ "]*-quickshell-[^/ "]*/bin/quickshell' \
  "$(dirname "$hearth_bin")/../libexec/hearth-shell" "$hearth_bin" 2>/dev/null | head -1)
[[ -x $qs ]] || { echo "can't find quickshell for $hearth_bin" >&2; exit 2; }

mkdir -p "$state_root/hearth-smoke"
work=$(mktemp -d "$state_root/hearth-smoke/lock.XXXXXX")
run=$(mktemp -d "/run/user/$(id -u)/hl.XXXX")
chmod 700 "$run"
log() { echo "lock-test: $*" | tee -a "$work/summary" >&2; }

ours() {
  local p
  for p in /proc/[0-9]*; do
    grep -qsa "XDG_RUNTIME_DIR=$run" "$p/environ" 2>/dev/null && echo "${p#/proc/}"
  done
}
cleanup() {
  ((keep)) && { log "kept: $work ($run)"; return; }
  local pids
  pids=$(ours | grep -vx "$$"); [[ -n $pids ]] && kill $pids 2>/dev/null
  sleep 0.5
  pids=$(ours | grep -vx "$$"); [[ -n $pids ]] && kill -9 $pids 2>/dev/null
  [[ -f $work/dbus.pid ]] && kill "$(cat "$work/dbus.pid")" 2>/dev/null
  if [[ -n ${kwin_pid:-} ]]; then
    kill -- "-$kwin_pid" "$kwin_pid" 2>/dev/null; sleep 0.3
    kill -9 -- "-$kwin_pid" "$kwin_pid" 2>/dev/null
  fi
  rm -rf "$run"
}
trap cleanup EXIT

real_home=$HOME
export HOME=$work/home XDG_CONFIG_HOME=$work/home/.config XDG_CACHE_HOME=$work/home/.cache \
  XDG_STATE_HOME=$work/home/.local/state XDG_DATA_HOME=$work/home/.local/share XDG_RUNTIME_DIR=$run
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY ARBOR_SOCKET NIRI_SOCKET NOTIFY_SOCKET \
  HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
# HEARTH_LOCK_PAM_DIR: test mode (no real PAM, no hyprlock fallback).
export QT_WAYLAND_RECONNECT=1 HEARTH_POLKIT=0 HEARTH_APPMENU_REGISTRAR=0 HEARTH_SESSION_DRYRUN=1 \
  QT_QPA_PLATFORM=wayland HEARTH_LOCK_PAM_DIR=$work/pam
mkdir -p "$XDG_CONFIG_HOME/arbor" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$work/kwin" "$work/pam"

printf '%s\n' '<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"' \
  ' "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">' \
  '<busconfig><type>session</type>' "<listen>unix:dir=$run</listen>" '<auth>EXTERNAL</auth>' \
  '<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>' \
  '</busconfig>' >"$work/dbus.conf"
dbus-daemon --config-file="$work/dbus.conf" --fork --print-address=1 --print-pid=3 >"$work/dbus.addr" 3>"$work/dbus.pid" ||
  { log "can't start dbus"; exit 2; }
export DBUS_SESSION_BUS_ADDRESS=$(cat "$work/dbus.addr")

# (Real HOME for KWin: with a fresh one and the private bus it was killed
# within a second here, 2026-11-21. Its config still goes to $work/kwin.)
HOME=$real_home XDG_CONFIG_HOME=$work/kwin setsid env -u QT_QPA_PLATFORM -u QT_WAYLAND_RECONNECT -u HEARTH_LOCK_PAM_DIR \
  -u XDG_CACHE_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME kwin_wayland --virtual --no-lockscreen --socket=kwin \
  --width 3840 --height 1620 >"$work/kwin.log" 2>&1 </dev/null &
kwin_pid=$!
for _ in $(seq 100); do [[ -S $run/kwin ]] && break; sleep 0.1; done
[[ -S $run/kwin ]] || { log "nested KWin didn't start"; exit 2; }

sed -e '/^spawn-/d' -e 's/^output "DP-1"/output "winit"/' -e '/mode "[0-9]*x[0-9]*/d' \
  -e '/hdr {/,/}/d' -e '/variable-refresh-rate/d' \
  "$repo/arbor/config.kdl" >"$XDG_CONFIG_HOME/arbor/config.kdl"
cp "$repo"/arbor/*.kdl.* "$repo/arbor/hearth-layer-rules.kdl" "$XDG_CONFIG_HOME/arbor/" 2>/dev/null

log "arbor $arbor_bin, hearth $hearth_bin"
# (KWin's socket can be up before it takes clients: try a few times.)
sleep 1
for try in 1 2 3; do
  WAYLAND_DISPLAY=kwin setsid "$arbor_bin" -c "$XDG_CONFIG_HOME/arbor/config.kdl" \
    >"$work/arbor.log" 2>&1 </dev/null &
  arbor_pid=$!
  for _ in $(seq 150); do
    grep -aq "listening on Wayland socket" "$work/arbor.log" && break 2
    kill -0 "$arbor_pid" 2>/dev/null || break
    sleep 0.1
  done
  sleep 1
done
wl=$(grep -ao 'listening on Wayland socket: [^ ]*' "$work/arbor.log" | head -1 | awk '{print $NF}')
[[ -n $wl ]] || { log "arbor didn't start"; exit 2; }
export WAYLAND_DISPLAY=$wl ARBOR_SOCKET=$(ls "$run"/arbor.*.sock 2>/dev/null | head -1)

shells() { # running quickshells of this session, oldest first
  local p
  for p in $(ours); do
    [[ $(readlink "/proc/$p/exe" 2>/dev/null) == *quickshell* ]] && grep -qa -- "-p" "/proc/$p/cmdline" && echo "$p"
  done | sort -n
}
ipc() { local p=$1; shift; timeout 5 "$qs" ipc --pid "$p" call "$@" 2>>"$work/ipc.log"; }
wait_new_shell() { # wait_new_shell EXCLUDE -> pid of a shell other than EXCLUDE
  local p
  for _ in $(seq 300); do
    for p in $(shells); do [[ $p != "$1" ]] && { echo "$p"; return 0; }; done
    sleep 0.1
  done
  return 1
}
wait_secure() { # wait_secure PID SECONDS
  for _ in $(seq $(($2 * 5))); do
    [[ $(ipc "$1" lock isSecure) == true ]] && return 0
    sleep 0.2
  done
  return 1
}

rc=1
setsid "$hearth_bin" >"$work/hearth-a.log" 2>&1 </dev/null &
wrapper_a=$!
a=$(wait_new_shell none) || { log "hearth A didn't start"; exit 1; }
sleep 3
ipc "$a" lock lock manual
if ! wait_secure "$a" 10; then log "FAIL: hearth A couldn't lock"; exit 1; fi
log "hearth A ($a) holds the lock"

setsid "$hearth_bin" >"$work/hearth-b.log" 2>&1 </dev/null &
b=$(wait_new_shell "$a") || { log "hearth B didn't start"; exit 1; }
log "hearth B ($b) started while A holds the lock"
# Let B's restore lock be refused at least once.
for _ in $(seq 100); do grep -aq "refusing lock as already locked" "$work/arbor.log" && break; sleep 0.1; done
grep -aq "refusing lock as already locked" "$work/arbor.log" && log "arbor refused B's lock (A alive)" ||
  log "note: no refusal seen in arbor's log"
sleep "$delay"
if ((term)); then
  log "stopping A with TERM through its wrapper"
  kill -TERM "$wrapper_a"
else
  log "killing A's quickshell"
  kill -9 "$a"
fi
t0=$(date +%s)
# B restarts itself to ask again (a new pid each time): follow whichever
# shell is not A.
ok=0
while (( $(date +%s) - t0 < 45 )); do
  for p in $(shells); do
    [[ $p == "$a" ]] && continue
    [[ $(ipc "$p" lock isSecure) == true ]] && { ok=1; b=$p; break 2; }
  done
  sleep 0.2
done
if ((ok)); then
  log "PASS: hearth B ($b) holds the lock $(( $(date +%s) - t0 )) s after A went"
  grep -a "replacing existing dead lock" "$work/arbor.log" | tail -1 | sed 's/\x1b\[[0-9;]*m//g; s/^/  arbor: /' >&2
  rc=0
else
  log "FAIL: hearth B never got the lock; shells: $(shells | tr '\n' ' ')"
fi
kill -0 "$a" 2>/dev/null && { log "FAIL: A ($a) is still running"; rc=1; }
grep -a "hearth lock\|starting it again\|starting the shell again" "$work/hearth-b.log" | sed 's/\x1b\[[0-9;]*m//g; s/^/  B: /' >&2
exit $rc
