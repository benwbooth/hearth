self:
# Shared pieces of the Electron/Chromium app modules in this folder.
#
# Why these apps need a wrapper on the Hearth desktop at all:
# - Wayland: Electron picks X11 unless told otherwise
#   (ELECTRON_OZONE_PLATFORM_HINT=auto); nixpkgs' wrappers only add the
#   Wayland flags with NIXOS_OZONE_WL=1, which Hearth doesn't set (through
#   XWayland the apps were scaled twice and didn't fit the side area).
# - The keyring: Chromium picks a password store from the desktop's name,
#   and arbor says "arbor:KDE" (so apps like Zoom treat it as KDE), so on
#   their own they'd ask KWallet, which Hearth doesn't run (oo7 is its
#   Secret Service), and fall back to an unencrypted store, losing every
#   cookie they can't decrypt. --password-store=gnome-libsecret asks the
#   Secret Service.
# - No Wayland colour management: under HDR, Chromium tags its windows with
#   its own SDR luminance and they came out dim; untagged they get the
#   monitor's SDR brightness like every other window.
# - The global menu: hearth reads Electron menus that aren't exported (an
#   auto-hidden menu bar, a menu drawn in the page, a ☰) over AT-SPI, and
#   Electron only builds that tree with `self.lib.globalMenu.electronFlags`
#   (or with a screen reader running). See nix/global-menu.nix.
{ lib, pkgs }:
rec {
  # makeWrapper arguments that pass the global-menu flags.
  globalMenuArgs = map (f: "--add-flags ${f}") self.lib.globalMenu.electronFlags;

  # Wayland, the Secret Service, no colour management; `args` are more
  # makeWrapper arguments (globalMenuArgs, an app's own fixes).
  wrapWayland = { exe, package, args ? [ ] }: pkgs.symlinkJoin {
    name = "${exe}-ozone";
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm $out/bin/${exe}
      makeWrapper ${package}/bin/${exe} $out/bin/${exe} \
        --set ELECTRON_OZONE_PLATFORM_HINT auto \
        --add-flags --password-store=gnome-libsecret \
        --add-flags --disable-features=WaylandWpColorManagerV1 ${lib.concatStringsSep " " args}
    '';
  };

  # Only the global menu and the Secret Service (apps that already run on
  # Wayland or that are fine on XWayland).
  wrapGlobalMenu = { exe, package }: pkgs.symlinkJoin {
    name = "${exe}-a11y";
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/${exe} ${lib.concatStringsSep " " globalMenuArgs} --add-flags --password-store=gnome-libsecret";
  };

  # A module for an app wrapped with one of the above:
  #   hearth.apps.<name> = { enable; package; extraWrapperArgs; }
  # extraConfig: more NixOS settings while the app is enabled.
  mkApp = { name, description, wrap, defaultPackage ? null, defaultPackageText ? null, extraConfig ? { } }:
    { config, lib, pkgs, ... }:
    let cfg = config.hearth.apps.${name}; in
    {
      options.hearth.apps.${name} = {
        enable = lib.mkEnableOption description;
        package = lib.mkOption ({
          type = lib.types.package;
          description = "The ${name} package to adjust.";
        } // lib.optionalAttrs (defaultPackage != null) {
          default = defaultPackage pkgs;
          defaultText = lib.literalExpression defaultPackageText;
        });
        extraWrapperArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "--unset QT_PLUGIN_PATH" ];
          description = "More makeWrapper arguments for the launcher (this machine's own fixes).";
        };
      };
      config = lib.mkIf cfg.enable (lib.mkMerge [
        { environment.systemPackages = [ (wrap { inherit (cfg) package extraWrapperArgs; }) ]; }
        extraConfig
      ]);
    };
}
