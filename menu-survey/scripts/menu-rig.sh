#!/usr/bin/env bash
# (menu-survey copy of the global-menu rig: hearth gets DISPLAY.)
# Nested arbor + installed hearth on a PRIVATE session bus, for checking that
# an app's global menu reaches hearth's menu bar. Never touches the live bus.
#
#   menu-rig.sh start            # private dbus + kwin --virtual + arbor + hearth
#   menu-rig.sh run CMD ARGS...  # run an app inside (env: bus, wayland, kde theme)
#   menu-rig.sh dump             # hearth-ipc call appmenu dump
#   menu-rig.sh ipc ARGS...      # any hearth ipc call
#   menu-rig.sh busctl ARGS...   # busctl --user on the private bus
#   menu-rig.sh kill NAME        # kill rig processes named NAME (never the live ones)
#   menu-rig.sh env              # print exports for the private session
#   menu-rig.sh stop
set -euo pipefail
R=${MENU_RIG_DIR:-$XDG_RUNTIME_DIR/menu-rig}
H=${HEARTH_PKG:-$(dirname "$(dirname "$(readlink -f "$(command -v hearth-ipc 2>/dev/null || echo /nix/store/lb9wb4nsv30p16d3prr882nqnncg1wcx-hearth-0.1.0/bin/hearth-ipc)")")")}
[[ -x $H/libexec/hearth-shell ]] || H=/nix/store/lb9wb4nsv30p16d3prr882nqnncg1wcx-hearth-0.1.0
QS=$(grep -oE '/nix/store/[^ ]*quickshell-[^/ ]*/bin/quickshell' "$H/bin/hearth-ipc" | head -1)
cmd=${1:?command}; shift || true

daemon() { local pidfile=$1 log=$2; shift 2
  setsid bash -c 'echo $$ > "$0"; exec "$@"' "$pidfile" "$@" >"$log" 2>&1 </dev/null &
  for _ in $(seq 40); do [[ -s $pidfile ]] && break; sleep 0.05; done; }

priv_env() {
  export DBUS_SESSION_BUS_ADDRESS=$(cat "$R/bus")
  export GSETTINGS_BACKEND=memory
  export HOME=$R/home XDG_CONFIG_HOME=$R/home/.config XDG_CACHE_HOME=$R/home/.cache
  export XDG_DATA_HOME=$R/home/.local/share XDG_STATE_HOME=$R/home/.local/state
  export XDG_CURRENT_DESKTOP=arbor:KDE XDG_SESSION_DESKTOP=arbor
  export QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=kde
  unset DISPLAY
  [[ -s $R/arbor.env ]] && { export WAYLAND_DISPLAY=$(grep ^WAYLAND_DISPLAY= "$R/arbor.env" | cut -d= -f2-)
    export ARBOR_SOCKET=$(grep -E '^(ARBOR|NIRI)_SOCKET=' "$R/arbor.env" | head -1 | cut -d= -f2-)
    export NIRI_SOCKET=$ARBOR_SOCKET; }
  return 0
}
hearth_pid() { # this rig's hearth (hearth-shell execs quickshell), never another rig's
  local p; p=$(cat "$R/hearth.pid" 2>/dev/null); [[ -n $p ]] && kill -0 "$p" 2>/dev/null && { echo "$p"; return; }
  echo "menu-rig: this rig's hearth is not running" >&2; }

case $cmd in
start)
  mkdir -p "$R/home/.config" "$R/home/.cache" "$R/home/.local/share" "$R/home/.local/state"
  cat > "$R/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=$R/bus.sock</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
EOF
  daemon "$R/dbus.pid" "$R/dbus.log" dbus-daemon --nofork --config-file="$R/bus.conf"
  for _ in $(seq 50); do [[ -S $R/bus.sock ]] && break; sleep 0.1; done
  echo "unix:path=$R/bus.sock" > "$R/bus"
  priv_env
  sock=menu-rig-kwin-$(basename "$R")
  XDG_CONFIG_HOME=$R/kwin-config WAYLAND_DISPLAY= daemon "$R/kwin.pid" "$R/kwin.log" \
    "$(readlink -f /run/current-system/sw/bin/kwin_wayland)" --virtual --no-lockscreen --socket=$sock --width 2600 --height 1500
  for _ in $(seq 80); do [[ -S $XDG_RUNTIME_DIR/$sock ]] && break; sleep 0.1; done
  mkdir -p "$R/home/.config/arbor"
  printf 'prefer-no-csd\nhotkey-overlay { skip-at-startup; }\n' > "$R/home/.config/arbor/config.kdl"
  rm -f "$R/arbor.env"
  WAYLAND_DISPLAY=$sock ARBOR_NO_SUPERVISOR=1 daemon "$R/arbor.pid" "$R/arbor.log" \
    arbor -c "$R/home/.config/arbor/config.kdl" -- bash -c "env > '$R/arbor.env.tmp'; mv '$R/arbor.env.tmp' '$R/arbor.env'; exec sleep infinity"
  for _ in $(seq 100); do [[ -s $R/arbor.env ]] && break; sleep 0.1; done
  [[ -s $R/arbor.env ]] || { echo "arbor did not start; see $R/arbor.log" >&2; exit 1; }
  priv_env
  # The nested arbor's window fills a 2560x1440 KWin output (hearth's menu
  # bar drops menus that don't fit beside its status items at 1280 wide).
  echo 'for (const w of workspace.windowList()) { if (w.normalWindow) { w.noBorder = true; w.frameGeometry = {x: 0, y: 0, width: 2560, height: 1440}; } }' > "$R/resize.js"
  busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss "$R/resize.js" resize >/dev/null
  busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting start
  # hearth reads X11 windows' menus with xprop: it needs the satellite's
  # DISPLAY, as arbor gives it in a real session (priv_env unsets it for
  # apps, which get it explicitly when they should be X11).
  DISPLAY=$(grep ^DISPLAY= "$R/arbor.env" | cut -d= -f2-) \
    HEARTH_SESSION_DRYRUN=1 HEARTH_POLKIT=0 daemon "$R/hearth.pid" "$R/hearth.log" "$H/libexec/hearth-shell"
  sleep 4
  echo "rig up: WAYLAND_DISPLAY=$WAYLAND_DISPLAY bus=$DBUS_SESSION_BUS_ADDRESS hearth pid=$(hearth_pid)"
  ;;
env) priv_env; env | grep -E '^(DBUS_SESSION_BUS_ADDRESS|GSETTINGS_BACKEND|HOME|XDG_[A-Z_]*HOME|XDG_CURRENT_DESKTOP|QT_QPA_[A-Z]*|WAYLAND_DISPLAY|ARBOR_SOCKET|NIRI_SOCKET)=' | sed 's/^/export /' ;;
run) priv_env
  # Apps get their own runtime and temp dirs, so single-instance sockets and
  # lock files never meet the live session's (or another session's) copy.
  mkdir -p -m 700 "$R/run" "$R/tmp"
  export WAYLAND_DISPLAY=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$R/run TMPDIR=$R/tmp
  exec "$@" ;;
dump) priv_env; exec "$QS" ipc --pid "$(hearth_pid)" call appmenu dump ;;
ipc) priv_env; exec "$QS" ipc --pid "$(hearth_pid)" "$@" ;;
busctl) priv_env; exec busctl --user "$@" ;;
kill) # kill NAME: only processes on this rig's private bus
  for pid in $(pgrep -x "${1:?process name}"); do
    { tr '\0' '\n' < /proc/$pid/environ; } 2>/dev/null | grep -qx "DBUS_SESSION_BUS_ADDRESS=unix:path=$R/bus.sock" && kill "$pid" && echo "killed $pid"
  done; true ;;
stop)
  for p in hearth arbor kwin dbus; do
    [[ -f $R/$p.pid ]] && kill -- -"$(cat "$R/$p.pid")" 2>/dev/null || true
  done
  sleep 0.5; rm -rf "$R" ;;
*) echo "unknown command $cmd" >&2; exit 2 ;;
esac
