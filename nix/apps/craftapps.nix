self:
# storytold's ArtCraft apps (gridcraft, deckcraft, wordcraft, ...; the
# nix-craftapps flake's `programs.craftapps`) on Wayland, not X11.
#
# Several of them open their window through XWayland whenever DISPLAY is
# set: winit, their windowing library, takes no file drops on Wayland, so
# they chose X11 for drag-and-drop (gridcraft 0.19.1 main.rs: unless
# GRIDCRAFT_WAYLAND is set). photocraft and vectorcraft do the same only
# with a pen tablet plugged in, for its pressure (unless
# <APP>_NATIVE_WAYLAND is set). As X11 windows arbor can't size them well
# and the global menu sees less of them. Each app's own switch keeps it on
# Wayland; the cost is no files dragged in from the file manager (open them
# with File > Open) and, with a pen, no pressure.
#
# Only when the nix-craftapps module is imported. Each wrapped package is a
# default: an explicit `programs.craftapps.apps.<name>.package` still wins.
{ config, lib, options, pkgs, ... }:
let
  cfg = config.hearth.apps.craftapps;
  # The app's switch that keeps native Wayland (from each app's source).
  switches = {
    cadcraft = "CADCRAFT_WAYLAND";
    deckcraft = "DECKCRAFT_WAYLAND";
    designcraft = "DESIGNCRAFT_WAYLAND";
    filmcraft = "FILMCRAFT_WAYLAND";
    gridcraft = "GRIDCRAFT_WAYLAND";
    lightcraft = "LIGHTCRAFT_WAYLAND";
    soundcraft = "SOUNDCRAFT_WAYLAND";
    wordcraft = "WORDCRAFT_WAYLAND";
    photocraft = "PHOTOCRAFT_NATIVE_WAYLAND";
    vectorcraft = "VECTORCRAFT_NATIVE_WAYLAND";
  };
  wrap = name: var: pkg: pkgs.symlinkJoin {
    name = "${pkg.name}-hearth";
    paths = [ pkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${name} --set-default ${var} 1
    '';
    inherit (pkg) meta;
  };
  hasCraftapps = options ? programs && options.programs ? craftapps;
in
{
  options.hearth.apps.craftapps.enable =
    lib.mkEnableOption "the ArtCraft apps on Wayland (their own switch; nix-craftapps module)";

  config = lib.mkIf cfg.enable (lib.optionalAttrs hasCraftapps {
    programs.craftapps.apps = lib.mapAttrs (name: var: {
      package = lib.mkDefault (wrap name var options.programs.craftapps.apps.${name}.package.default);
    }) (lib.filterAttrs (name: _: options.programs.craftapps.apps ? ${name}) switches);
  });
}
