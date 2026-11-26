#!/usr/bin/env bash
# Headless test session for hearth: arbor on its headless backend (its own
# HOME and private bus, so it never touches the real session's) is the
# compositor, and hearth runs on it from this checkout. Works while the real
# screen is locked, and several named sessions can run side by side.
#
#   scripts/test-session.sh start NAME     # headless arbor
#   scripts/test-session.sh run NAME       # (re)start hearth from ./shell
#   scripts/test-session.sh shot NAME [OUT.png]   # full screenshot (3840x1620)
#   scripts/test-session.sh msg NAME ARGS...      # arbor msg against that instance
#   scripts/test-session.sh ipc NAME ARGS...      # hearth-ipc against that instance
#   scripts/test-session.sh env NAME       # its WAYLAND_DISPLAY/ARBOR_SOCKET, for eval
#   scripts/test-session.sh log NAME       # hearth's log
#   scripts/test-session.sh stop NAME
#
# The output is 3840x1620 at scale 1 (Ben's 5120x2160 at 4/3 in logical
# pixels). arbor runs the repo's arbor/config.kdl without startup programs,
# HDR or VRR. hearth gets its own XDG_CONFIG_HOME/XDG_CACHE_HOME/XDG_STATE_HOME
# under the session dir (HEARTH_TEST_XDG_CONFIG etc. to point elsewhere) but
# the real session bus (the tray shows the real apps). Tools come from
# /etc/nixos's nixpkgs; arbor is devloop's (or ARBOR_BIN), as it needs the
# headless backend.
set -euo pipefail

cmd=${1:?command}
name=${2:?session name}
shift 2 || true
repo=$(cd "$(dirname "$0")/.." && pwd)
dir=$XDG_RUNTIME_DIR/hearth-test/$name
mkdir -p "$dir"

tool() { # tool ATTR -> store path (cached per session dir)
  local f=$XDG_RUNTIME_DIR/hearth-test/.tool-$1
  if [[ ! -s $f ]]; then
    nix build --no-link --print-out-paths --inputs-from /etc/nixos "nixpkgs#$1" | tail -1 > "$f"
  fi
  cat "$f"
}
quickshell() {
  local f=$XDG_RUNTIME_DIR/hearth-test/.tool-quickshell
  if [[ ! -s $f ]]; then
    nix build --no-link --print-out-paths "$repo#quickshell" | tail -1 > "$f"
  fi
  cat "$f"
}

# daemon PIDFILE LOG CMD...: run CMD detached, recording its real pid.
daemon() {
  local pidfile=$1 log=$2; shift 2
  setsid bash -c 'echo $$ > "$0"; exec "$@"' "$pidfile" "$@" >"$log" 2>&1 </dev/null &
  for _ in $(seq 20); do [[ -s $pidfile ]] && break; sleep 0.05; done
}

# The hearth package's runtime PATH (ddcutil, cliphist, python with dbus...).
runtime_path() {
  local f=$XDG_RUNTIME_DIR/hearth-test/.runtime-path
  if [[ ! -s $f ]]; then
    local p; p=$(nix build --no-link --print-out-paths "$repo#hearth" | tail -1)
    local w=$p/libexec/hearth-shell; [[ -e $w ]] || w=$p/bin/hearth
    grep -oE "'/nix/store/[^']+/bin'" "$w" | tr -d "'" | sort -u | paste -sd: > "$f"
  fi
  cat "$f"
}

way() { cat "$dir/wayland"; }
arbor_sock() { cat "$dir/arbor-socket"; }

case $cmd in
start)
  if [[ -s $dir/wayland && -S $XDG_RUNTIME_DIR/$(cat "$dir/wayland") && -S $(cat "$dir/arbor-socket" 2>/dev/null) ]]; then
    echo "session $name already running: WAYLAND_DISPLAY=$(way) ARBOR_SOCKET=$(arbor_sock)"
    exit 0
  fi
  source "$repo/scripts/headless-arbor.sh"
  arbor_bin=$(headless_arbor_bin "${ARBOR_BIN:-}")
  echo "$arbor_bin" >"$dir/arbor-bin"
  # arbor gets its own HOME (window memory, state) and a bus with nothing to
  # activate: its D-Bus services must not meet the real ones.
  ah=$dir/arbor-home
  mkdir -p "$ah/.config/arbor" "$ah/.cache" "$ah/.local/share" "$ah/.local/state" "$dir/config/hearth"
  # The config's "~/.config/hearth/arbor-*.kdl" includes: the test shell's.
  ln -sfn "$dir/config/hearth" "$ah/.config/hearth"
  printf '%s\n' '<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"' \
    ' "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">' \
    "<busconfig><type>session</type><listen>unix:path=$dir/host-bus</listen><auth>EXTERNAL</auth>" \
    '<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>' \
    >"$dir/host-bus.conf"
  daemon "$dir/host-dbus.pid" "$dir/host-dbus.log" dbus-daemon --nofork --config-file="$dir/host-bus.conf"
  for _ in $(seq 50); do [[ -S $dir/host-bus ]] && break; sleep 0.1; done
  # Ben's config without startup programs (no second hearth, vicinae...).
  sed -e '/^spawn-/d' -e '/hdr {/,/}/d' -e '/variable-refresh-rate/d' \
    "$repo/arbor/config.kdl" >"$ah/.config/arbor/config.kdl"
  cp "$repo/arbor/hearth-layer-rules.kdl" "$ah/.config/arbor/"
  ( headless_arbor_env headless-1=3840x1620
    export HOME=$ah XDG_CONFIG_HOME=$ah/.config XDG_CACHE_HOME=$ah/.cache XDG_DATA_HOME=$ah/.local/share \
      XDG_STATE_HOME=$ah/.local/state DBUS_SESSION_BUS_ADDRESS=unix:path=$dir/host-bus ARBOR_NO_SUPERVISOR=1
    unset WAYLAND_DISPLAY WAYLAND_SOCKET DISPLAY ARBOR_SOCKET NIRI_SOCKET NOTIFY_SOCKET HYPRLAND_INSTANCE_SIGNATURE
    daemon "$dir/arbor.pid" "$dir/arbor.log" "$arbor_bin" -c "$ah/.config/arbor/config.kdl" )
  for _ in $(seq 100); do grep -aq "listening on Wayland socket" "$dir/arbor.log" 2>/dev/null && break; sleep 0.1; done
  grep -ao 'listening on Wayland socket: [^ ]*' "$dir/arbor.log" | head -1 | awk '{print $NF}' >"$dir/wayland"
  [[ -s $dir/wayland ]] || { echo "headless arbor did not start; see $dir/arbor.log" >&2; exit 1; }
  echo "$XDG_RUNTIME_DIR/arbor.$(way).$(cat "$dir/arbor.pid").sock" >"$dir/arbor-socket"
  for _ in $(seq 50); do ARBOR_SOCKET=$(arbor_sock) timeout 2 "$arbor_bin" msg version >/dev/null 2>&1 && break; sleep 0.1; done
  ARBOR_SOCKET=$(arbor_sock) timeout 2 "$arbor_bin" msg version >/dev/null 2>&1 ||
    { echo "headless arbor does not answer on $(arbor_sock); see $dir/arbor.log" >&2; exit 1; }
  echo "session $name: WAYLAND_DISPLAY=$(way) ARBOR_SOCKET=$(arbor_sock)"
  ;;
run)
  # The whole group (daemon starts it with setsid): the shell's long-lived
  # helpers (udisksctl/nmcli monitor, ...) outlive a shell killed on its own.
  [[ -f $dir/qs.pid ]] && kill -- -"$(cat "$dir/qs.pid")" 2>/dev/null || true
  sleep 0.3
  mkdir -p "$dir/state" "$dir/cache" "$dir/config"
  ( unset HYPRLAND_INSTANCE_SIGNATURE NIRI_SOCKET DISPLAY WAYLAND_SOCKET NOTIFY_SOCKET
    export WAYLAND_DISPLAY=$(way) ARBOR_SOCKET=$(arbor_sock) QT_QPA_PLATFORM=wayland \
      HEARTH_FONT_DIR="${HEARTH_FONT_DIR:-$(tool inter)/share/fonts/truetype}" \
      HEARTH_POLKIT=0 HEARTH_APPMENU_REGISTRAR=${HEARTH_APPMENU_REGISTRAR:-0} \
      HEARTH_SESSION_DRYRUN=${HEARTH_SESSION_DRYRUN:-1} HEARTH_NOTIFICATIONS=${HEARTH_NOTIFICATIONS:-0} \
      HEARTH_KEYRING_PROMPTER=${HEARTH_KEYRING_PROMPTER:-0} HEARTH_PORTAL=${HEARTH_PORTAL:-0} \
      HEARTH_AI_MANAGE_DRYRUN=${HEARTH_AI_MANAGE_DRYRUN:-1} \
      GSETTINGS_BACKEND=memory \
      XDG_CONFIG_HOME=${HEARTH_TEST_XDG_CONFIG:-$dir/config} XDG_CACHE_HOME=${HEARTH_TEST_XDG_CACHE:-$dir/cache} \
      XDG_STATE_HOME=${HEARTH_TEST_XDG_STATE:-$dir/state} \
      PATH="${HEARTH_TEST_PATH:+$HEARTH_TEST_PATH:}$repo/helpers:$(runtime_path):$(dirname "$(cat "$dir/arbor-bin")"):$PATH"
    daemon "$dir/qs.pid" "$dir/qs.log" "$(quickshell)/bin/quickshell" -p "$repo/shell" )
  sleep 3
  grep -E 'ERROR|WARN|error' "$dir/qs.log" | grep -vE 'accessibility|host portal|Empty key' || true
  ;;
shot)
  out=${1:-$dir/shot.png}
  timeout 20 env WAYLAND_DISPLAY="$(way)" "$(tool grim)/bin/grim" "$out"
  echo "$out"
  ;;
msg)
  ARBOR_SOCKET=$(arbor_sock) timeout 10 "$(cat "$dir/arbor-bin")" msg "$@"
  ;;
ipc)
  WAYLAND_DISPLAY=$(way) ARBOR_SOCKET=$(arbor_sock) \
    "$(quickshell)/bin/quickshell" -p "$repo/shell" ipc "$@"
  ;;
env)
  echo "export WAYLAND_DISPLAY=$(way) ARBOR_SOCKET=$(arbor_sock)"
  ;;
log)
  cat "$dir/qs.log"
  ;;
stop)
  # Each daemon is its own setsid group: the shell's helpers die with it.
  for p in qs arbor host-dbus; do
    [[ -f $dir/$p.pid ]] && kill -- -"$(cat "$dir/$p.pid")" 2>/dev/null || true
  done
  sleep 0.5
  for p in qs arbor host-dbus; do
    [[ -f $dir/$p.pid ]] && kill -9 -- -"$(cat "$dir/$p.pid")" 2>/dev/null || true
  done
  rm -rf "$dir"
  ;;
*)
  echo "unknown command $cmd" >&2; exit 2 ;;
esac
