self:
# Slack: its menu bar is auto-hidden, so it isn't exported; hearth's
# global menu reads it over AT-SPI (the global-menu flags), and its keys
# go to the Secret Service (electron.nix says why).
{ lib, pkgs, ... }@args:
let e = import ./electron.nix self { inherit lib pkgs; }; in
e.mkApp {
  name = "slack";
  description = "Slack, adjusted for the Hearth desktop (global menu, Secret Service)";
  defaultPackage = p: p.slack;
  defaultPackageText = "pkgs.slack";
  wrap = { package, extraWrapperArgs }: e.wrapGlobalMenu { exe = "slack"; inherit package; };
} args
