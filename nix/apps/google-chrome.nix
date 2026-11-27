self:
# Google Chrome with the Secret Service: arbor says "arbor:KDE", so it
# would ask KWallet, which Hearth doesn't run, and lose its cookies
# (electron.nix says more).
{ config, lib, pkgs, ... }:
let cfg = config.hearth.apps.google-chrome; in
{
  options.hearth.apps.google-chrome = {
    enable = lib.mkEnableOption "Google Chrome, adjusted for the Hearth desktop (Secret Service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.google-chrome;
      defaultText = lib.literalExpression "pkgs.google-chrome";
      description = "The Chrome package to adjust (anything with nixpkgs' commandLineArgs override).";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (cfg.package.override { commandLineArgs = lib.concatStringsSep " "
        ([ "--password-store=gnome-libsecret" ] ++ self.lib.globalMenu.electronFlags); })
    ];
  };
}
