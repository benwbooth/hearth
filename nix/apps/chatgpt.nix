self:
# The ChatGPT/Codex desktop app on Wayland with the Secret Service
# (electron.nix says why). It exports no window menu (only its tray icon's):
# its menu is drawn in the page and read over AT-SPI (wrapWayland's
# global-menu flags), opened unseen while the user is in the global menu
# (arbor ProbeWindow freezes the window's picture). No package in nixpkgs
# that matches: pass one.
{ lib, pkgs, ... }@args:
let e = import ./electron.nix self { inherit lib pkgs; }; in
e.mkApp {
  name = "chatgpt";
  description = "ChatGPT desktop, adjusted for the Hearth desktop (Wayland, Secret Service)";
  # The app picks X11 itself (it ignores ELECTRON_OZONE_PLATFORM_HINT), so say Wayland
  # outright. Under XWayland its own title bar couldn't move the window: xwayland-satellite
  # dropped its _NET_WM_MOVERESIZE (it sends button 0). Renders fine on Wayland now (2026-11-28).
  wrap = { package, extraWrapperArgs }: e.wrapWayland {
    exe = "chatgpt"; inherit package;
    args = [ "--add-flags --ozone-platform=wayland" ] ++ extraWrapperArgs;
  };
} args
