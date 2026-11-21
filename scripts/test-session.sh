#!/usr/bin/env bash
# Headless test session for hearth: a virtual KWin hosts a nested Hyprland,
# and hearth runs inside that from this checkout. Works while the real
# screen is locked, and several named sessions can run side by side.
#
#   scripts/test-session.sh start NAME     # KWin + Hyprland
#   scripts/test-session.sh run NAME       # (re)start hearth from ./shell
#   scripts/test-session.sh shot NAME [OUT.png]   # full screenshot (3840x1620)
#   scripts/test-session.sh hyprctl NAME ARGS...  # talk to the nested Hyprland
#   scripts/test-session.sh ipc NAME ARGS...      # hearth-ipc against that instance
#   scripts/test-session.sh log NAME       # hearth's log
#   scripts/test-session.sh stop NAME
#
# The nested output is 3840x1620 at scale 1 (Ben's 5120x2160 at 4/3 in
# logical pixels). Tools come from /etc/nixos's nixpkgs.
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
    grep -oE "'/nix/store/[^']+/bin'" "$p/bin/hearth" | tr -d "'" | sort -u | paste -sd: > "$f"
  fi
  cat "$f"
}

hypr_sig() { cat "$dir/sig"; }
hypr_wayland() { cat "$dir/wayland"; }

case $cmd in
start)
  sock=hearth-kwin-$name
  if ! [[ -S $XDG_RUNTIME_DIR/$sock ]]; then
    # Own config dir: KWin writes [Xwayland] Scale from its outputs into
    # kwinrc, and the 1x virtual output would reset the real session's 1.3.
    mkdir -p "$dir/kwin-config"
    WAYLAND_DISPLAY= DISPLAY= XDG_CONFIG_HOME="$dir/kwin-config" daemon "$dir/kwin.pid" "$dir/kwin.log" \
      kwin_wayland --virtual --no-lockscreen --socket="$sock" --width 4000 --height 1720
    for _ in $(seq 50); do [[ -S $XDG_RUNTIME_DIR/$sock ]] && break; sleep 0.1; done
  fi
  cat > "$dir/hyprland.lua" <<'EOF'
hl.monitor({ output = "", mode = "3840x1620", position = "0x0", scale = "1" })
hl.config({
  misc = { disable_hyprland_logo = true, force_default_wallpaper = 0 },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
EOF
  # HEARTH_TEST_CONFIG=FILE: run that config instead (e.g. the real
  # hyprland.lua with its monitor and autostart taken out), with the repo's
  # Lua modules next to it and the title bar plugin from the uwsm env.
  if [[ -n ${HEARTH_TEST_CONFIG:-} ]]; then
    cp "$repo"/hypr/*.lua "$dir/"
    cp "$HEARTH_TEST_CONFIG" "$dir/hyprland.lua"
    [[ -f ~/.config/uwsm/env-hyprland ]] && source ~/.config/uwsm/env-hyprland
  fi
  before=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null || true)
  (cd "$dir" && WAYLAND_DISPLAY=$sock daemon "$dir/hypr.pid" "$dir/hypr.log" \
    "$(tool hyprland)/bin/Hyprland" --config "$dir/hyprland.lua")
  for _ in $(seq 100); do
    sig=$(comm -13 <(echo "$before" | sort) <(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | sort) | head -1)
    # Ask Hyprland for its socket: a stale wayland-N file can be reused.
    way=""
    [[ -n $sig && -S $XDG_RUNTIME_DIR/hypr/$sig/.socket.sock ]] &&
      way=$("$(tool hyprland)/bin/hyprctl" instances -j 2>/dev/null | jq -r --arg s "$sig" '.[] | select(.instance == $s) | .wl_socket')
    [[ -n $sig && -n $way ]] && break
    sleep 0.1
  done
  [[ -n ${sig:-} && -n ${way:-} ]] || { echo "Hyprland did not start; see $dir/hypr.log" >&2; exit 1; }
  echo "$sig" > "$dir/sig"
  echo "$way" > "$dir/wayland"
  echo "session $name: HYPRLAND_INSTANCE_SIGNATURE=$sig WAYLAND_DISPLAY=$way"
  ;;
run)
  [[ -f $dir/qs.pid ]] && kill "$(cat "$dir/qs.pid")" 2>/dev/null || true
  sleep 0.3
  HYPRLAND_INSTANCE_SIGNATURE=$(hypr_sig) WAYLAND_DISPLAY=$(hypr_wayland) QT_QPA_PLATFORM=wayland \
    HEARTH_FONT_DIR="${HEARTH_FONT_DIR:-$(tool inter)/share/fonts/truetype}" \
    HEARTH_POLKIT=0 \
    PATH="${HEARTH_TEST_PATH:+$HEARTH_TEST_PATH:}$repo/helpers:$(runtime_path):$(tool hyprland)/bin:$PATH" XDG_STATE_HOME="$dir/state" \
    daemon "$dir/qs.pid" "$dir/qs.log" "$(quickshell)/bin/quickshell" -p "$repo/shell"
  sleep 3
  grep -E 'ERROR|WARN|error' "$dir/qs.log" | grep -vE 'accessibility|host portal|Empty key' || true
  ;;
shot)
  out=${1:-$dir/shot.png}
  timeout 20 env WAYLAND_DISPLAY="$(hypr_wayland)" "$(tool grim)/bin/grim" "$out"
  echo "$out"
  ;;
hyprctl)
  HYPRLAND_INSTANCE_SIGNATURE=$(hypr_sig) "$(tool hyprland)/bin/hyprctl" "$@"
  ;;
ipc)
  HYPRLAND_INSTANCE_SIGNATURE=$(hypr_sig) WAYLAND_DISPLAY=$(hypr_wayland) \
    "$(quickshell)/bin/quickshell" -p "$repo/shell" ipc "$@"
  ;;
log)
  cat "$dir/qs.log"
  ;;
stop)
  for p in qs hypr kwin; do
    [[ -f $dir/$p.pid ]] && kill -- -"$(cat "$dir/$p.pid")" 2>/dev/null || true
  done
  sleep 0.5
  # Hyprland leaves a watchdog child outside its process group.
  for p in $(pgrep Hyprland); do
    tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | grep -q -- "--config $dir/hyprland.lua" && kill -9 "$p"
  done
  [[ -f $dir/sig ]] && rm -rf "$XDG_RUNTIME_DIR/hypr/$(cat "$dir/sig")"
  rm -rf "$dir"
  ;;
*)
  echo "unknown command $cmd" >&2; exit 2 ;;
esac
