self:
# ZCode on Wayland with the Secret Service (electron.nix says why).
#
# The Wayland hint is also set session-wide: ZCode rewrites
# ~/.local/share/applications/zcode.desktop on every launch to register
# its zcode:// handler, taking Exec from process.execPath -- the raw store
# binary, which bypasses the wrapper. Launched from the menu it then missed
# the hint, fell back to XWayland and was scaled twice (XWayland's scale,
# then Chromium's Xft.dpi): ~1.69x. Every Electron app Hearth wraps already
# sets this to "auto", so it changes no other app.
# No package in nixpkgs: pass one.
{ lib, pkgs, ... }@args:
let e = import ./electron.nix self { inherit lib pkgs; }; in
e.mkApp {
  name = "zcode";
  description = "ZCode, adjusted for the Hearth desktop (Wayland, Secret Service)";
  wrap = { package, extraWrapperArgs }: e.wrapWayland {
    exe = "zcode"; inherit package;
    args = extraWrapperArgs;
  };
  extraConfig.environment.sessionVariables.ELECTRON_OZONE_PLATFORM_HINT = "auto";
} args
