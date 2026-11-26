self:
# Visual Studio Code with the Secret Service: arbor says "arbor:KDE", so it
# would ask KWallet, which Hearth doesn't run, and lose its sign-ins
# (electron.nix says more).
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.apps.vscode;
  adjusted = cfg.package.override { commandLineArgs = "--password-store=gnome-libsecret"; };
in
{
  options.hearth.apps.vscode = {
    enable = lib.mkEnableOption "Visual Studio Code, adjusted for the Hearth desktop (Secret Service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.vscode;
      defaultText = lib.literalExpression "pkgs.vscode";
      description = "The VS Code package to adjust (anything with nixpkgs' commandLineArgs override).";
    };
    fhs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install its FHS-environment build (`.fhs`), where extensions' downloaded binaries run.";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ (if cfg.fhs then adjusted.fhs else adjusted) ];
  };
}
