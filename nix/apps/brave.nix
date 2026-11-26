self:
# Brave on Wayland, with the Secret Service, without Wayland colour
# management (electron.nix says why for each). The keyring matters most
# here: without its key (carried over from KWallet's "Brave Keys") Brave
# deletes every cookie it can't decrypt. --disable-features comes last:
# Chromium keeps only the last --disable-features, so add more features
# to that one rather than in extraFlags.
{ config, lib, pkgs, ... }:
let cfg = config.hearth.apps.brave; in
{
  options.hearth.apps.brave = {
    enable = lib.mkEnableOption "Brave, adjusted for the Hearth desktop (Wayland, Secret Service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.brave;
      defaultText = lib.literalExpression "pkgs.brave";
      description = "The Brave package to adjust (anything with nixpkgs' commandLineArgs override).";
    };
    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--enable-features=TouchpadOverscrollHistoryNavigation" ];
      description = "More command-line flags.";
    };
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (cfg.package.override {
        commandLineArgs = lib.concatStringsSep " " ([
          "--ozone-platform=wayland"
          "--password-store=gnome-libsecret"
        ] ++ cfg.extraFlags ++ [
          "--disable-features=WaylandWpColorManagerV1"
        ]);
      })
    ];
  };
}
