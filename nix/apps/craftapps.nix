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
#
# Global menus: their macOS menu bar, which Linux builds don't have, or for
# the four with none (deckcraft, figcraft, pdfcraft, wordcraft) their ribbon
# or in-app menu from their command catalog. Each app has a localhost JSON-
# lines control server that lists the menu the Mac menu bar is built from
# and runs its items; hearth-appmenu reads it (CraftMenu; gridcraft's from
# its source, menus/craft/gridcraft.json). The launcher turns the server on:
# a free 127.0.0.1 port per run, a fresh token where the app takes one
# (gridcraft, photocraft, filmcraft; cadcraft and wordcraft make their own;
# pdfcraft takes `--control FILE` and writes its port and token there),
# recorded for hearth in $XDG_RUNTIME_DIR/hearth/craft/<pid>.json (0600 in
# a 0700 folder; the token is also in the app's environment, which only you
# can read). Not when a copy of the app already runs with one: with a
# control port photocraft runs as its own process instead of handing the
# file to the open window.
#
# Exposure: 127.0.0.1 is reachable by every local process of every user.
# deckcraft, designcraft, effectcraft, figcraft, lightcraft, soundcraft and
# vectorcraft check no token, so such a process could run their menu
# commands (open, save, export...). The servers reject HTTP, so web pages
# can't reach them. Ben's choice (2026-11-26); a Unix socket in the runtime
# folder (a preloaded bind() shim) would close it.
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
  # Control servers: the token variable where the app takes one from us.
  control = {
    cadcraft = { };
    deckcraft = { };
    designcraft = { };
    effectcraft = { };
    figcraft = { };
    filmcraft = { token = "FILMCRAFT_CONTROL_TOKEN"; };
    gridcraft = { token = "GRIDCRAFT_CONTROL_TOKEN"; };
    lightcraft = { };
    # (No port switch: `--control FILE`, where it writes its own port and token.)
    pdfcraft = { file = true; };
    photocraft = { token = "PHOTOCRAFT_CONTROL_TOKEN"; };
    soundcraft = { };
    vectorcraft = { };
    wordcraft = { };
  };
  cu = "${pkgs.coreutils}/bin";
  controlScript = name: c: pkgs.writeText "${name}-hearth-control" (
    let port = "${lib.toUpper name}_CONTROL_PORT"; in ''
      # hearth: a control port for the global menu (nix/apps/craftapps.nix).
      if [ -z "''${${port}:-}" ] && [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ "''${1:-}" != --control ]; then
        _hd="$XDG_RUNTIME_DIR/hearth/craft"
        (umask 077; ${cu}/mkdir -p "$_hd")
        _hrun=
        for _hf in "$_hd"/*.json; do
          [ -e "$_hf" ] || continue
          _hp=''${_hf##*/}; _hp=''${_hp%.json}
          if [ -d "/proc/$_hp" ]; then
            ${pkgs.gnugrep}/bin/grep -q '"app":"${name}"' "$_hf" && _hrun=1
          else
            ${cu}/rm -f "$_hf"
          fi
        done
        if [ -z "$_hrun" ]; then
        ${if c.file or false then ''
          _hctl="$_hd/${name}-$$.ctl"
          ${cu}/rm -f "$_hctl"
          set -- --control "$_hctl" "$@"
          (umask 077; printf '{"app":"${name}","control_file":"%s"}\n' "$_hctl" > "$_hd/$$.json")
        '' else ''
          for _ht in 1 2 3 4 5 6 7 8; do
            _hport=$(( 40000 + (RANDOM * 32768 + RANDOM) % 20000 ))
            (exec 3<>"/dev/tcp/127.0.0.1/$_hport") 2>/dev/null || break
          done
          _htok=$(${cu}/od -An -N32 -tx1 /dev/urandom | ${cu}/tr -d ' \n')
          export ${port}="$_hport"
          ${lib.optionalString (c ? token) ''export ${c.token}="$_htok"''}
          (umask 077; printf '{"app":"${name}","port":%s,"token":"%s"}\n' "$_hport" "${if c ? token then "$_htok" else ""}" > "$_hd/$$.json")
        ''}
        fi
      fi
    '');
  wrap = name: pkg: pkgs.symlinkJoin {
    name = "${pkg.name}-hearth";
    paths = [ pkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${name} \
        ${lib.optionalString (switches ? ${name}) "--set-default ${switches.${name}} 1"} \
        ${lib.optionalString (control ? ${name}) "--run '. ${controlScript name control.${name}}'"}
    '';
    inherit (pkg) meta;
  };
  hasCraftapps = options ? programs && options.programs ? craftapps;
in
{
  options.hearth.apps.craftapps.enable =
    lib.mkEnableOption "the ArtCraft apps on Wayland (their own switch) with their Mac menus in the global menu (nix-craftapps module)";

  config = lib.mkIf cfg.enable (lib.optionalAttrs hasCraftapps {
    programs.craftapps.apps = lib.mapAttrs (name: _: {
      package = lib.mkDefault (wrap name options.programs.craftapps.apps.${name}.package.default);
    }) (lib.filterAttrs (name: _: options.programs.craftapps.apps ? ${name}) (switches // control));
  });
}
