#!/usr/bin/env bash
# Smoke test for a new arbor or hearth build before it goes live (devloop's
# arbor and hearth apps run it first; on failure the running version stays).
#
#   scripts/smoke-test.sh [--arbor BIN] [--hearth BIN] [--no-reload] [--keep]
#
# Runs BIN (default: devloop's build, else the one on PATH) in a throwaway
# session: arbor on its headless backend (a 5120x2160 "DP-1" drawn offscreen
# on the 7900 XTX, no host compositor), a private D-Bus, its own HOME and
# runtime dir, Ben's arbor config (DP-1 at 4/3), no startup programs. Starts
# hearth, opens tray menus, Settings, the overview, the screenshot overlay
# (screencopy) with a new window opening on top, and the screenshot editor;
# restarts arbor in place (reload-binary) and checks the shell comes back.
# Fails on an arbor panic or restart, a shell crash or core dump, or a QML
# error. Exit 0: passed. Logs of failed runs stay in
# $XDG_STATE_HOME/hearth-smoke/.
set -uo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
state_root=${XDG_STATE_HOME:-$HOME/.local/state}
arbor_bin="" hearth_bin="" reload=1 keep=0
while (($#)); do
  case $1 in
    --arbor) arbor_bin=$2; shift 2 ;;
    --hearth) hearth_bin=$2; shift 2 ;;
    --no-reload) reload=0; shift ;;
    --keep) keep=1; shift ;;
    *) echo "usage: $0 [--arbor BIN] [--hearth BIN] [--no-reload] [--keep]" >&2; exit 2 ;;
  esac
done
source "$repo/scripts/headless-arbor.sh"
arbor_bin=$(headless_arbor_bin "$arbor_bin") || exit 2
if [[ -z $hearth_bin ]]; then
  hearth_bin=$state_root/devloop/hearth/bin/hearth
  [[ -x $hearth_bin ]] || hearth_bin=$(command -v hearth) || { echo "no hearth" >&2; exit 2; }
fi
hearth_bin=$(readlink -f "$hearth_bin")
# The quickshell the hearth wrapper runs (for `quickshell ipc`).
qs=$(grep -ho '/nix/store/[^ "]*-quickshell-[^/ "]*/bin/quickshell' \
  "$(dirname "$hearth_bin")/../libexec/hearth-shell" "$hearth_bin" 2>/dev/null | head -1)
[[ -x $qs ]] || { echo "can't find quickshell for $hearth_bin" >&2; exit 2; }

mkdir -p "$state_root/hearth-smoke"
work=$(mktemp -d "$state_root/hearth-smoke/run.XXXXXX")
# Short: Unix socket paths are limited to 108 bytes.
run=$(mktemp -d "/run/user/$(id -u)/hs.XXXX")
chmod 700 "$run"
log() { echo "smoke: $*" | tee -a "$work/summary" >&2; }
fails=()
fail() { fails+=("$*"); log "FAIL: $*"; }

ours() { # pids of processes in this test session (by runtime dir)
  local p
  for p in /proc/[0-9]*; do
    grep -qsa "XDG_RUNTIME_DIR=$run" "$p/environ" 2>/dev/null && echo "${p#/proc/}"
  done
}
cleanup() {
  local pids
  pids=$(ours | grep -vx "$$")
  [[ -n $pids ]] && kill $pids 2>/dev/null
  sleep 0.5
  pids=$(ours | grep -vx "$$")
  [[ -n $pids ]] && kill -9 $pids 2>/dev/null
  [[ -f $work/dbus.pid ]] && kill "$(cat "$work/dbus.pid")" 2>/dev/null
  fusermount -u "$run/doc" 2>/dev/null
  rm -rf "$run"
}
trap cleanup EXIT

export HOME=$work/home XDG_CONFIG_HOME=$work/home/.config XDG_CACHE_HOME=$work/home/.cache \
  XDG_STATE_HOME=$work/home/.local/state XDG_DATA_HOME=$work/home/.local/share XDG_RUNTIME_DIR=$run
unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY ARBOR_SOCKET NIRI_SOCKET NOTIFY_SOCKET \
  HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
# As in the arbor session; a test shell must never act on the real session.
# (Platform theme as arbor/config.kdl sets it.)
export QT_WAYLAND_RECONNECT=1 HEARTH_POLKIT=0 HEARTH_APPMENU_REGISTRAR=0 HEARTH_SESSION_DRYRUN=1 \
  QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=xdgdesktopportal
mkdir -p "$XDG_CONFIG_HOME/arbor" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

# A private bus with nothing to activate: the real session's services
# (portals, the keyring...) must not start in here.
printf '%s\n' '<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"' \
  ' "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">' \
  '<busconfig><type>session</type>' "<listen>unix:dir=$run</listen>" '<auth>EXTERNAL</auth>' \
  '<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>' \
  '</busconfig>' >"$work/dbus.conf"
dbus-daemon --config-file="$work/dbus.conf" --fork --print-address=1 --print-pid=3 >"$work/dbus.addr" 3>"$work/dbus.pid" ||
  { log "can't start dbus"; exit 2; }
export DBUS_SESSION_BUS_ADDRESS=$(cat "$work/dbus.addr")

# Headless arbor with Ben's monitor (scripts/headless-arbor.sh).
headless_arbor_env DP-1=5120x2160

# Ben's config, without startup programs, HDR or VRR.
sed -e '/^spawn-/d' -e '/hdr {/,/}/d' -e '/variable-refresh-rate/d' \
  "$repo/arbor/config.kdl" >"$XDG_CONFIG_HOME/arbor/config.kdl"
cp "$repo"/arbor/*.kdl.* "$repo/arbor/hearth-layer-rules.kdl" "$XDG_CONFIG_HOME/arbor/" 2>/dev/null

log "arbor $arbor_bin, hearth $hearth_bin"
setsid "$arbor_bin" --supervise -c "$XDG_CONFIG_HOME/arbor/config.kdl" \
  >"$work/arbor.log" 2>&1 </dev/null &
sock=""
for _ in $(seq 150); do
  sock=$(ls "$run"/arbor.*.sock 2>/dev/null | head -1)
  [[ -n $sock ]] && grep -aq "listening on Wayland socket" "$work/arbor.log" && break
  sleep 0.1
done
wl=$(grep -ao 'listening on Wayland socket: [^ ]*' "$work/arbor.log" | head -1 | awk '{print $NF}')
if [[ -z $sock || -z $wl ]]; then
  fail "arbor didn't start: $(grep -a -m1 -E 'panicked|Error' "$work/arbor.log")"
fi
x11=$(grep -ao 'listening on X11 socket: :[0-9]*' "$work/arbor.log" | head -1 | awk '{print $NF}')
export ARBOR_SOCKET=$sock WAYLAND_DISPLAY=$wl DISPLAY=$x11
amsg() { timeout 5 "$arbor_bin" msg "$@" 2>>"$work/msg.log"; }

shellpid() { # the running quickshell of this session
  local p
  for p in $(ours); do
    [[ $(readlink "/proc/$p/exe" 2>/dev/null) == *quickshell* ]] && grep -qa -- "-p" "/proc/$p/cmdline" && { echo "$p"; return; }
  done
}
ipc() { # call a hearth IPC function, then note what's on screen
  local p; p=$(shellpid)
  [[ -n $p ]] || { echo "ipc $*: no shell" >>"$work/trace"; return; }
  timeout 5 "$qs" ipc --pid "$p" call "$@" >>"$work/ipc.log" 2>&1
  { echo "== ipc $* (exit $?)"; sleep 0.3
    amsg layers | grep -o 'Namespace: "[^"]*"' | sort | uniq -c | tr '\n' ' '; echo
    amsg windows | grep -E '^  (Title|App ID):' | paste - - ; } >>"$work/trace" 2>&1
}
wait_shell() { # until the menu bar is up
  for _ in $(seq 300); do
    amsg layers | grep -q hearth-menubar && [[ -n $(shellpid) ]] && return 0
    sleep 0.1
  done
  return 1
}

if ((${#fails[@]} == 0)); then
  setsid "$hearth_bin" >"$work/hearth.log" 2>&1 </dev/null &
  if ! wait_shell; then
    fail "hearth's menu bar didn't come up"
  else
    sleep 2
    log "exercising the shell"
    for ind in clipboard zones network drives ai weather keyboard bluetooth volume; do
      ipc "indicator-$ind" toggle; sleep 0.4; ipc "indicator-$ind" toggle; sleep 0.2
    done
    # The screenshot overlay shows a screencopy of the output; windows that
    # open meanwhile enter that output (Qt crashed on this: Quickshell's
    # screencopy bound a wl_output Qt took for one of its screens).
    ipc screenshot open; sleep 1.5
    ipc settings open; sleep 1.5
    ipc about open; sleep 1.5
    ipc screenshot-overlay capture; sleep 2
    # Those windows now leave and re-enter the output (the crash came on a
    # screen change after the capture had ended).
    for id in $(amsg -j windows | jq -r '.[].id'); do
      amsg action minimize-window --id "$id"; sleep 0.3
      amsg action restore-window --id "$id"; sleep 0.3
      amsg action move-window-to-workspace --window-id "$id" --focus false 2; sleep 0.3
      amsg action move-window-to-workspace --window-id "$id" --focus false 1; sleep 0.3
    done
    echo "== windows left and re-entered" >>"$work/trace"
    ipc settings openPane displays; sleep 1
    ipc overview open; sleep 1.5
    ipc overview close; sleep 0.5
    ipc screenshot screen; sleep 2.5
    if ((reload)); then
      log "restarting arbor in place"
      before=$(shellpid)
      amsg action reload-binary
      sleep 2
      wait_shell || fail "hearth didn't come back after an in-place restart"
      [[ $(shellpid) == "$before" ]] && log "note: the shell kept its process across the restart"
      ipc overview open; sleep 1; ipc overview close
    fi
    sleep 3
  fi
fi

# --- verdict ---
if grep -aqE "compositor crashed|panicked" "$work/arbor.log"; then
  fail "arbor: $(grep -a -m1 -E 'compositor crashed|panicked' "$work/arbor.log" | sed 's/.*\(compositor crashed\|panicked\)/\1/')"
fi
if [[ -n ${sock:-} ]] && ! amsg version >/dev/null; then
  fail "arbor isn't answering"
fi
if [[ -z $(shellpid) && ${#fails[@]} -eq 0 ]]; then
  fail "hearth isn't running at the end"
fi
if [[ -d $XDG_CACHE_HOME/quickshell/crashes ]] && [[ -n $(ls -A "$XDG_CACHE_HOME/quickshell/crashes" 2>/dev/null) ]]; then
  fail "hearth crashed (Quickshell crash report in $XDG_CACHE_HOME/quickshell/crashes)"
fi
if grep -aqE "Segmentation fault|core dumped|exited with status (134|139)" "$work/hearth.log" 2>/dev/null; then
  fail "hearth crashed: $(grep -a -m1 -E 'Segmentation fault|core dumped|status (134|139)' "$work/hearth.log")"
fi
# QML errors, minus what a bare test session can't have (no PipeWire,
# portals, Hyprland, devloop, accessibility bus, tray watcher...).
# Not the old shell's teardown when arbor restarts (exit 75: bindings
# evaluated while the engine is being destroyed give "Unable to assign
# [undefined]"); the shell started again after it is checked as usual.
qml_errors=$(awk '/arbor restarted: restarting the shell/{t=1} /starting the shell again/{t=0} !t' "$work/hearth.log" 2>/dev/null |
  grep -aE "ReferenceError|TypeError|SyntaxError|is not defined|is not a function|Cannot (read|assign)|Type error|Unable to assign|QML .*: .*[Ee]rror|ERROR" |
  grep -avE "pipewire|portal|hyprctl|devloop|atspi|StatusNotifier|sni\.host|fprint|pam|NetworkManager|nmcli|bluez|upower|ddcutil|geoclue|recoll|ollama|llama|whisper|Detailed logger failed to write" | sort -u)
# Quickshell's own detailed log couldn't be written: /run/user (a small
# tmpfs) was full for a moment, nothing wrong with the shell. Noted, not a
# failure (it held back a deploy on 2026-11-25).
if grep -aq "Detailed logger failed to write" "$work/hearth.log" 2>/dev/null; then
  echo "smoke: note: Quickshell's detailed log couldn't be written (is /run/user full? $(df -h --output=pcent "/run/user/$(id -u)" 2>/dev/null | tail -1 | tr -d ' ') used)"
fi
if [[ -n $qml_errors ]]; then
  fail "QML errors:"$'\n'"$(head -10 <<<"$qml_errors")"
fi

if ((${#fails[@]})); then
  log "FAILED (logs: $work)"
  exit 1
fi
log "passed"
# Stop the session first: its processes still write under $work.
cleanup; trap - EXIT
((keep)) || rm -rf "$work"
# Keep the last 5 failed runs.
ls -dt "$state_root"/hearth-smoke/run.* 2>/dev/null | grep -vxF "$work" | tail -n +6 | xargs -r rm -rf
exit 0
