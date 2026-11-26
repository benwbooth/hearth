self:
# Cursor on Wayland with the Secret Service, no colour management and the
# global-menu flags (its menu is drawn in the page); electron.nix says why.
# It replaces nixpkgs' launcher (which passes --update=false and adds the
# Wayland flags only with NIXOS_OZONE_WL) with one on the unwrapped
# binary. --force-device-scale-factor=1: on Wayland the compositor scales
# it; Chromium's own guess scaled it a second time.
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.apps.cursor;
  e = import ./electron.nix self { inherit lib pkgs; };
  wrapped = pkgs.symlinkJoin {
    name = "cursor-wayland";
    paths = [ cfg.package ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      # Replace the nixpkgs wrapper that passes --update=false
      rm $out/bin/cursor
      makeWrapper ${cfg.package}/bin/.cursor-wrapped $out/bin/cursor \
        --set ELECTRON_OZONE_PLATFORM_HINT auto \
        --unset NIXOS_OZONE_WL \
        --add-flags --force-device-scale-factor=1 \
        --add-flags --password-store=gnome-libsecret \
        --add-flags --disable-features=WaylandWpColorManagerV1 \
        ${lib.concatStringsSep " " (e.globalMenuArgs ++ cfg.extraWrapperArgs)}
    '';
  };
in
{
  options.hearth.apps.cursor = {
    enable = lib.mkEnableOption "Cursor, adjusted for the Hearth desktop (Wayland, global menu, Secret Service)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.code-cursor;
      defaultText = lib.literalExpression "pkgs.code-cursor";
      description = "The Cursor package to adjust (nixpkgs' code-cursor or a build of it).";
    };
    extraWrapperArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "More makeWrapper arguments for the launcher.";
    };
  };
  config = lib.mkIf cfg.enable { environment.systemPackages = [ wrapped ]; };
}
