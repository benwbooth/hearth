self:
# Spotify on Wayland, always.
#
# Spotify sets Chromium's (CEF's) ozone-platform itself: whenever DISPLAY is
# set it adds --ozone-platform=x11, over any --ozone-platform=wayland we
# pass (its binary: `if (getenv("DISPLAY")) append_switch("ozone-platform",
# "x11")`; tested on 1.2.90 / CEF 146 with dead displays, 2026-11-26).
# Older versions honoured our flag. As an X11 window (through
# xwayland-satellite) it declares a minimum width of 1063-1600 px, so arbor
# can't fit it into the side area; on Wayland it fits. nixpkgs' wrapper
# drops DISPLAY too, but only with NIXOS_OZONE_WL=1, which Hearth doesn't
# set. So the launcher drops it: there's no X display to choose.
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.apps.spotify;
  wrapped = pkgs.symlinkJoin {
    name = "${cfg.package.name}-hearth";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/spotify \
        --unset DISPLAY \
        --add-flags "--enable-features=UseOzonePlatform" \
        --add-flags "--ozone-platform=wayland"
    '';
  };
in
{
  options.hearth.apps.spotify = {
    enable = lib.mkEnableOption "Spotify, adjusted for the Hearth desktop (always on Wayland)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.spotify;
      defaultText = lib.literalExpression "pkgs.spotify";
      example = lib.literalExpression "inputs.spicetify-nix.lib.mkSpicetify pkgs { }";
      description = "The Spotify package to adjust (a spicetify build works too).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wrapped ];
  };
}
