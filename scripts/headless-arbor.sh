# Sourced by the test rigs: arbor on its own headless backend as the
# session's compositor (no host compositor, nothing from KDE). Outputs are
# drawn offscreen on the GPU; screencopy, screenshots and the lock work.
#
#   headless_arbor_bin [BIN]     # prints BIN, devloop's arbor or the one on PATH; fails
#                                # unless it has the headless backend
#   headless_arbor_env OUTPUTS   # exports ARBOR_BACKEND=headless etc. for arbor;
#                                # OUTPUTS: [NAME=]WxH[,...], e.g. DP-1=5120x2160
#
# Without the backend an arbor with no WAYLAND_DISPLAY would start on the
# TTY backend (the real seat), hence the check.

headless_arbor_bin() {
  local bin=${1:-}
  if [[ -z $bin ]]; then
    bin=${XDG_STATE_HOME:-$HOME/.local/state}/devloop/arbor/bin/arbor
    [[ -x $bin ]] || bin=$(command -v arbor) || { echo "no arbor" >&2; return 1; }
  fi
  grep -qa ARBOR_HEADLESS_OUTPUTS "$(readlink -f "$bin")" || {
    echo "$bin has no headless backend (ARBOR_BACKEND=headless); use a newer arbor (--arbor BIN)" >&2
    return 1
  }
  echo "$bin"
}

headless_arbor_env() {
  export ARBOR_BACKEND=headless ARBOR_HEADLESS_OUTPUTS=$1
  # The 7900 XTX (Mesa would pick the Raphael iGPU, ~6x slower).
  local gpu=/dev/dri/by-path/pci-0000:03:00.0-render
  [[ -e $gpu ]] && export ARBOR_HEADLESS_RENDER_NODE=$gpu
  # Nothing in a test session may write the real dconf.
  export GSETTINGS_BACKEND=memory
}
