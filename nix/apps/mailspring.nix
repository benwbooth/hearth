self:
# Mailspring on Wayland (Electron picks X11 unless told; nixpkgs' wrapper
# adds the flags only with NIXOS_OZONE_WL, which Hearth doesn't set). Its
# desktop entry points at the wrapped launcher, so the Dock and Spotlight
# start it on Wayland too.
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.apps.mailspring;
  wrapped = pkgs.symlinkJoin {
    name = "mailspring-wayland";
    paths = [ cfg.package ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/mailspring \
        --set ELECTRON_OZONE_PLATFORM_HINT auto \
        --add-flags "--enable-features=UseOzonePlatform" \
        --add-flags "--ozone-platform=wayland"
      rm $out/share/applications/Mailspring.desktop
      cp ${cfg.package}/share/applications/Mailspring.desktop $out/share/applications/Mailspring.desktop
      substituteInPlace $out/share/applications/Mailspring.desktop \
        --replace-quiet "${cfg.package}/bin/mailspring" "$out/bin/mailspring"
    '';
  };
in
{
  options.hearth.apps.mailspring = {
    enable = lib.mkEnableOption "Mailspring, adjusted for the Hearth desktop (Wayland)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.mailspring;
      defaultText = lib.literalExpression "pkgs.mailspring";
      description = "The Mailspring package to adjust.";
    };
  };
  config = lib.mkIf cfg.enable { environment.systemPackages = [ wrapped ]; };
}
