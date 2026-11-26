#!/usr/bin/env bash
# (menu-survey copy of the global-menu rig: hearth gets DISPLAY.)
# Headless arbor (no host compositor) + installed hearth on a PRIVATE session bus, for checking that
# an app's global menu reaches hearth's menu bar. Never touches the live bus.
#
#   menu-rig.sh start            # private dbus + headless arbor (2560x1440) + hearth
#                                # (arbor: ARBOR_BIN, else devloop's, else PATH's; needs
#                                # the headless backend)
#   menu-rig.sh run CMD ARGS...  # run an app inside (env: bus, wayland, kde theme)
#   menu-rig.sh dump             # hearth-ipc call appmenu dump
#   menu-rig.sh ipc ARGS...      # any hearth ipc call
#   menu-rig.sh busctl ARGS...   # busctl --user on the private bus
#   menu-rig.sh kill NAME        # kill rig processes named NAME (never the live ones)
#   menu-rig.sh env              # print exports for the private session
#   menu-rig.sh stop
set -euo pipefail
R=${MENU_RIG_DIR:-$XDG_RUNTIME_DIR/menu-rig}
# Homes, caches, Flatpak data and temp files on disk: /run/user is a small
# tmpfs (RAM) the live session needs; only sockets and pids stay there.
D=${MENU_RIG_DISK:-/var/tmp/menu-rig-$USER/$(basename "$R")}
H=${HEARTH_PKG:-$(dirname "$(dirname "$(readlink -f "$(command -v hearth-ipc 2>/dev/null || echo /nix/store/lb9wb4nsv30p16d3prr882nqnncg1wcx-hearth-0.1.0/bin/hearth-ipc)")")")}
[[ -x $H/libexec/hearth-shell ]] || H=/nix/store/lb9wb4nsv30p16d3prr882nqnncg1wcx-hearth-0.1.0
QS=$(grep -oE '/nix/store/[^ ]*quickshell-[^/ ]*/bin/quickshell' "$H/bin/hearth-ipc" | head -1)
cmd=${1:?command}; shift || true

daemon() { local pidfile=$1 log=$2; shift 2
  # Logs on disk, linked from $R: a chatty process once filled the 6 GB
  # /run/user tmpfs (2026-11-25/26).
  mkdir -p "$D/logs"
  ln -sfn "$D/logs/$(basename "$log")" "$log"
  setsid bash -c 'echo $$ > "$0"; exec "$@"' "$pidfile" "$@" >"$D/logs/$(basename "$log")" 2>&1 </dev/null &
  for _ in $(seq 40); do [[ -s $pidfile ]] && break; sleep 0.05; done; }

priv_env() {
  export DBUS_SESSION_BUS_ADDRESS=$(cat "$R/bus")
  export GSETTINGS_BACKEND=memory
  export HOME=$D/home XDG_CONFIG_HOME=$D/home/.config XDG_CACHE_HOME=$D/home/.cache
  export XDG_DATA_HOME=$D/home/.local/share XDG_STATE_HOME=$D/home/.local/state
  export XDG_CURRENT_DESKTOP=arbor:KDE XDG_SESSION_DESKTOP=arbor
  # As the live session (arbor/config.kdl): Qt's xdgdesktopportal theme.
  # Plasma's kde theme picks the org.kde.desktop style, whose Kirigami
  # hearth no longer has: hearth failed to load, every app looked menu-less.
  export QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=xdgdesktopportal
  unset DISPLAY
  # Never the real session's arbor: a rig process that inherited its socket
  # once powered off the real monitors (2026-11-24).
  unset ARBOR_SOCKET NIRI_SOCKET
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
  source "$(dirname "$(readlink -f "$0")")/../../scripts/headless-arbor.sh"
  arbor_bin=$(headless_arbor_bin "${ARBOR_BIN:-}")
  mkdir -p "$R" "$D/tmp" "$D/home/.config" "$D/home/.cache" "$D/home/.local/share" "$D/home/.local/state"
  cat > "$R/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=$R/bus.sock</listen><auth>EXTERNAL</auth>
<servicedir>$R/services</servicedir>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
EOF
  # Services the bus may start (the probe adds each app's own, from its
  # closure: evolution-data-server, gnome-terminal-server...). From the
  # system only an allow-list: never the keyring, the a11y bus (started
  # separately), systemd, your accounts or file manager.
  # The apps' runtime dir (Flatpak instances, sockets, whatever an app
  # writes to XDG_RUNTIME_DIR) on disk too, linked from $R/run: one app
  # once filled the 6 GB /run/user tmpfs (2026-11-25).
  mkdir -p "$R/services" "$D/run"
  chmod 700 "$D/run"
  [[ -L $R/run || ! -e $R/run ]] || rm -rf "${R:?}/run"
  ln -sfn "$D/run" "$R/run"
  for f in /run/current-system/sw/share/dbus-1/services/*.service /etc/profiles/per-user/$USER/share/dbus-1/services/*.service; do
    case $(basename "$f" .service) in
      ca.desrt.dconf|org.freedesktop.portal.Desktop|org.freedesktop.portal.Documents|org.freedesktop.portal.Flatpak|\
      org.freedesktop.impl.portal.desktop.gtk|org.freedesktop.impl.portal.PermissionStore|org.freedesktop.Flatpak|\
      org.gtk.vfs.*|org.gtk.GLib.PACRunner|org.mpris.MediaPlayer2.playerctld) ln -sf "$f" "$R/services/" ;;
    esac
  done
  # The bus and everything it starts live in the rig: its home and runtime
  # dir. (A service started with the real ones once rewrote the real dconf
  # and the live a11y bus socket.)
  daemon "$R/dbus.pid" "$R/dbus.log" env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    -u ARBOR_SOCKET -u NIRI_SOCKET \
    HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" \
    XDG_CACHE_HOME="$D/home/.cache" XDG_DATA_HOME="$D/home/.local/share" XDG_STATE_HOME="$D/home/.local/state" \
    XDG_RUNTIME_DIR="$R/run" TMPDIR="$D/tmp" \
    dbus-daemon --nofork --config-file="$R/bus.conf"
  for _ in $(seq 50); do [[ -S $R/bus.sock ]] && break; sleep 0.1; done
  echo "unix:path=$R/bus.sock" > "$R/bus"
  # Sound for apps that won't start without it (a PulseAudio server, JACK
  # through PipeWire's libjack): PipeWire in the rig, playing to a dummy
  # sink. WirePlumber's device monitors are off, so the rig never opens
  # your sound cards, Bluetooth or cameras.
  if command -v pipewire >/dev/null && command -v wireplumber >/dev/null && command -v pipewire-pulse >/dev/null; then
    mkdir -p "$D/home/.config/pipewire/pipewire.conf.d" "$D/home/.config/wireplumber/wireplumber.conf.d"
    cat > "$D/home/.config/pipewire/pipewire.conf.d/rig-null-sink.conf" <<'PW'
context.objects = [
  { factory = adapter
    args = { factory.name = support.null-audio-sink node.name = "rig-null" node.description = "Rig dummy output"
             media.class = "Audio/Sink" audio.position = [ FL FR ] } }
]
PW
    cat > "$D/home/.config/wireplumber/wireplumber.conf.d/rig-no-devices.conf" <<'WP'
wireplumber.profiles = {
  main = { monitor.alsa = disabled, monitor.alsa-midi = disabled, monitor.bluez = disabled,
           monitor.bluez-midi = disabled, monitor.v4l2 = disabled, monitor.libcamera = disabled }
}
WP
    for pw in pipewire wireplumber pipewire-pulse; do
      daemon "$R/$pw.pid" "$R/$pw.log" env -u DISPLAY -u WAYLAND_DISPLAY -u PIPEWIRE_REMOTE -u PULSE_SERVER \
        HOME="$D/home" XDG_CONFIG_HOME="$D/home/.config" XDG_STATE_HOME="$D/home/.local/state" \
        XDG_RUNTIME_DIR="$R/run" DBUS_SESSION_BUS_ADDRESS="unix:path=$R/bus.sock" "$pw"
      sleep 0.5
    done
  fi
  priv_env
  mkdir -p "$D/home/.config/arbor"
  printf 'prefer-no-csd\nhotkey-overlay { skip-at-startup; }\n' > "$D/home/.config/arbor/config.kdl"
  rm -f "$R/arbor.env"
  # 2560x1440: hearth's menu bar drops menus that don't fit beside its
  # status items at 1280 wide.
  ( headless_arbor_env headless-1=2560x1440
    unset WAYLAND_DISPLAY WAYLAND_SOCKET
    ARBOR_NO_SUPERVISOR=1 daemon "$R/arbor.pid" "$R/arbor.log" \
    "$arbor_bin" -c "$D/home/.config/arbor/config.kdl" -- bash -c "env > '$R/arbor.env.tmp'; mv '$R/arbor.env.tmp' '$R/arbor.env'; exec sleep infinity" )
  for _ in $(seq 100); do [[ -s $R/arbor.env ]] && break; sleep 0.1; done
  [[ -s $R/arbor.env ]] || { echo "arbor did not start; see $R/arbor.log" >&2; exit 1; }
  priv_env
  # What the bus starts opens its windows in the rig (gnome-terminal-server,
  # portal dialogs): the rig's displays, by absolute socket path (the
  # services' runtime dir is the rig's).
  dbus-update-activation-environment WAYLAND_DISPLAY="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" \
    DISPLAY="$(grep ^DISPLAY= "$R/arbor.env" | cut -d= -f2-)" XDG_CURRENT_DESKTOP="$XDG_CURRENT_DESKTOP" \
    >/dev/null 2>&1 || true
  # hearth reads X11 windows' menus with xprop: it needs the satellite's
  # DISPLAY, as arbor gives it in a real session (priv_env unsets it for
  # apps, which get it explicitly when they should be X11).
  # hearth with only its own Qt plugins and QML, as devloop starts it: the
  # session's QT_PLUGIN_PATH still has Plasma's kde platform theme (the
  # org.kde.desktop style, whose Kirigami hearth no longer ships).
  # Its sound (the volume chime) and volume controls on the rig's PipeWire
  # (the dummy sink), never yours: rigs once chimed on every volume change
  # (2026-11-25). No rig PipeWire: a remote that doesn't exist.
  if [[ -S $R/run/pipewire-0 ]]; then
    pwenv=(PIPEWIRE_RUNTIME_DIR="$R/run" PULSE_SERVER="unix:$R/run/pulse/native")
  else
    pwenv=(PIPEWIRE_REMOTE=rig-no-pipewire PULSE_SERVER=unix:/nonexistent)
  fi
  DISPLAY=$(grep ^DISPLAY= "$R/arbor.env" | cut -d= -f2-) \
    QT_PLUGIN_PATH= QML2_IMPORT_PATH= \
    HEARTH_SESSION_DRYRUN=1 HEARTH_POLKIT=0 daemon "$R/hearth.pid" "$R/hearth.log" env "${pwenv[@]}" "$H/libexec/hearth-shell"
  sleep 4
  echo "rig up: WAYLAND_DISPLAY=$WAYLAND_DISPLAY bus=$DBUS_SESSION_BUS_ADDRESS hearth pid=$(hearth_pid)"
  ;;
env) priv_env; env | grep -E '^(DBUS_SESSION_BUS_ADDRESS|GSETTINGS_BACKEND|HOME|XDG_[A-Z_]*HOME|XDG_CURRENT_DESKTOP|QT_QPA_[A-Z]*|WAYLAND_DISPLAY|ARBOR_SOCKET|NIRI_SOCKET)=' | sed 's/^/export /' ;;
run) priv_env
  # Apps get their own runtime and temp dirs, so single-instance sockets and
  # lock files never meet the live session's (or another session's) copy.
  mkdir -p -m 700 "$R/run" "$D/tmp"
  export WAYLAND_DISPLAY=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$R/run TMPDIR=$D/tmp
  exec "$@" ;;
dump) priv_env; exec "$QS" ipc --pid "$(hearth_pid)" call appmenu dump ;;
ipc) priv_env; exec "$QS" ipc --pid "$(hearth_pid)" "$@" ;;
busctl) priv_env; exec busctl --user "$@" ;;
kill) # kill NAME: only processes on this rig's private bus
  for pid in $(pgrep -x "${1:?process name}"); do
    { tr '\0' '\n' < /proc/$pid/environ; } 2>/dev/null | grep -qx "DBUS_SESSION_BUS_ADDRESS=unix:path=$R/bus.sock" && kill "$pid" && echo "killed $pid"
  done; true ;;
stop)
  # Everything on this rig's bus, the services it started too (Akonadi,
  # Evolution's data server, portals detach from the bus's process group).
  for pid in $(pgrep -u "$(id -u)"); do
    { tr '\0' '\n' < /proc/$pid/environ; } 2>/dev/null | grep -q "^DBUS_SESSION_BUS_ADDRESS=unix:path=$R/bus.sock\(,\|$\)" \
      && kill "$pid" 2>/dev/null
  done
  for p in hearth arbor pipewire-pulse wireplumber pipewire dbus; do
    [[ -f $R/$p.pid ]] && kill -- -"$(cat "$R/$p.pid")" 2>/dev/null || true
  done
  sleep 0.5
  # Apps leave read-only folders (Flatpak payloads): writable first.
  chmod -R u+rwX "${R:?}" "${D:?}" 2>/dev/null || true
  rm -rf "${R:?}" "${D:?}" ;;
*) echo "unknown command $cmd" >&2; exit 2 ;;
esac
