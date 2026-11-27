self:
# Freelens (Kubernetes IDE, Electron): it exports no menu, so hearth's
# global menu reads its in-window menus over AT-SPI with the global-menu
# flags; its keys go to the Secret Service (electron.nix says why).
{ lib, pkgs, ... }@args:
let e = import ./electron.nix self { inherit lib pkgs; }; in
e.mkApp {
  name = "freelens";
  description = "Freelens, adjusted for the Hearth desktop (global menu, Secret Service)";
  defaultPackage = p: p.freelens-bin;
  defaultPackageText = "pkgs.freelens-bin";
  wrap = { package, extraWrapperArgs }: e.wrapGlobalMenu { exe = "freelens"; inherit package; };
} args
