self:
# storytold's ArtCraft apps (gridcraft, deckcraft, wordcraft, ...; the
# nix-craftapps flake's `programs.craftapps`) on Wayland, not X11.
#
# Eight of them open their window through XWayland whenever DISPLAY is set
# (gridcraft 0.19.1 main.rs, unless GRIDCRAFT_WAYLAND is set): upstream
# winit took no file drops on Wayland. Their own winit fork has since
# learned them (storytold/winit cf73a29c, 2026-10-02, wayland/seat/dnd.rs,
# built into these releases) and gridcraft's main branch dropped the X11
# switch, so on Wayland nothing is lost. As X11 windows arbor can't size
# them well and the global menu sees less of them. Each app's own switch
# keeps it on Wayland.
#
# Not photocraft and vectorcraft: they open through XWayland only with a
# pen tablet plugged in, because winit doesn't bind Wayland's tablet
# protocol (zwp_tablet_v2), so on Wayland a pen does nothing in their
# window, not even move the pointer; XWayland serves it as an XInput2
# device with pressure and tilt (photocraft src/tablet.rs). Without a pen
# they're on Wayland already.
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
