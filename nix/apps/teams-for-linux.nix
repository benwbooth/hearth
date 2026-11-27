self:
# Teams for Linux with the Secret Service: arbor says "arbor:KDE", so it
# would ask KWallet, which Hearth doesn't run, and lose its sign-in
# (electron.nix says more).
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.apps.teams-for-linux;
  e = import ./electron.nix self { inherit lib pkgs; };
  wrapped = pkgs.symlinkJoin {
    name = "teams-for-linux";
    paths = [ cfg.package ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/teams-for-linux \
        --add-flags "--password-store=gnome-libsecret" \
        ${lib.concatStringsSep " " e.globalMenuArgs}
    '';
  };
in
{
  options.hearth.apps.teams-for-linux = {
    enable = lib.mkEnableOption "Teams for Linux, adjusted for the Hearth desktop (Secret Service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.teams-for-linux;
      defaultText = lib.literalExpression "pkgs.teams-for-linux";
      description = "The Teams for Linux package to adjust.";
    };
  };
  config = lib.mkIf cfg.enable { environment.systemPackages = [ wrapped ]; };
}
