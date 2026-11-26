self:
# Claude Desktop on Wayland with the Secret Service (electron.nix says
# why). It has no menu bar: hearth's global menu reads its ☰ menu over
# AT-SPI (the global-menu flags). No package in nixpkgs: pass one.
{ lib, pkgs, ... }@args:
let e = import ./electron.nix self { inherit lib pkgs; }; in
e.mkApp {
  name = "claude-desktop";
  description = "Claude Desktop, adjusted for the Hearth desktop (Wayland, global menu, Secret Service)";
  wrap = { package, extraWrapperArgs }: e.wrapWayland {
    exe = "claude-desktop"; inherit package;
    args = e.globalMenuArgs ++ extraWrapperArgs;
  };
} args
