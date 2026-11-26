self:
# Antigravity on Wayland with the Secret Service (electron.nix says why).
# Its menu is drawn in the page, not exported, so hearth's global menu
# reads it over AT-SPI (the global-menu flags).
{ lib, pkgs, ... }@args:
let e = import ./electron.nix self { inherit lib pkgs; }; in
e.mkApp {
  name = "antigravity";
  description = "Antigravity, adjusted for the Hearth desktop (Wayland, global menu, Secret Service)";
  defaultPackage = p: p.antigravity;
  defaultPackageText = "pkgs.antigravity";
  wrap = { package, extraWrapperArgs }: e.wrapWayland {
    exe = "antigravity"; inherit package;
    args = e.globalMenuArgs ++ extraWrapperArgs;
  };
} args
