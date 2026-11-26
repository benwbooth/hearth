self:
# The desktop portal on the Hearth desktop (README "Portal"):
#
#   imports = [ hearth.nixosModules.portal ];
#   hearth.portal = { enable = true; fileChooser = { name = "grove"; package = grove; }; };
#
# - hearth's own backend (helpers/hearth-portal) for most interfaces:
#   light/dark and accent for Qt, browsers, GTK 4 and Flatpaks;
#   notifications; permission, Open With, print and web app sheets;
#   Account, Email, Lockdown.
# - arbor is its own backend for screen sharing and screenshots for apps,
#   remote control, clipboard sharing, InputCapture, app global shortcuts,
#   "Set as wallpaper" and idle inhibit (no GNOME portal).
# - Open/save dialogs from whichever app `fileChooser` names (grove's on
#   Ben's machine); GTK apps ask the portal for them only with
#   GTK_USE_PORTAL=1 (GTK 3's GtkFileChooserNative) and GDK_DEBUG=portals
#   (GTK 4 unsandboxed): without them neither called it (2026-11-25).
# - Flatpaks' secrets from oo7's portal when hearth.keyring is on.
# The whole table is forced: arbor's module routes everything else to the
# GTK portal, and `xdg.portal.config.<desktop>` is one table per desktop.
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.portal;
  hearth = self.packages.${pkgs.stdenv.hostPlatform.system}.hearth;
in
{
  options.hearth.portal = {
    enable = lib.mkEnableOption "hearth's desktop portal backend and the Hearth desktop's portal table";
    desktop = lib.mkOption {
      type = lib.types.str;
      default = "arbor";
      description = "The XDG_CURRENT_DESKTOP name whose portal table this sets (arbor's session).";
    };
    fileChooser = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            example = "grove";
            description = "The backend's name (its share/xdg-desktop-portal/portals/<name>.portal).";
          };
          package = lib.mkOption {
            type = lib.types.package;
            description = "The package with that backend.";
          };
        };
      });
      default = null;
      description = "The open/save dialogs' portal backend; null leaves them to GTK's portal.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.portal.config.${cfg.desktop} = lib.mkForce ({
      default = [ "hearth" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "arbor" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "arbor" ];
      "org.freedesktop.impl.portal.RemoteDesktop" = [ "arbor" ];
      "org.freedesktop.impl.portal.Clipboard" = [ "arbor" ];
      "org.freedesktop.impl.portal.InputCapture" = [ "arbor" ];
      "org.freedesktop.impl.portal.GlobalShortcuts" = [ "arbor" ];
      "org.freedesktop.impl.portal.Wallpaper" = [ "arbor" ];
      "org.freedesktop.impl.portal.Inhibit" = [ "arbor" ];
    } // lib.optionalAttrs (cfg.fileChooser != null) {
      "org.freedesktop.impl.portal.FileChooser" = [ cfg.fileChooser.name ];
    } // lib.optionalAttrs (config.hearth.keyring.enable or false) {
      "org.freedesktop.impl.portal.Secret" = [ "oo7-portal" ];
    });
    xdg.portal.extraPortals = [ hearth ]  # hearth.portal
      ++ lib.optional (cfg.fileChooser != null) cfg.fileChooser.package;
    environment.sessionVariables = lib.mkIf (cfg.fileChooser != null) {
      GTK_USE_PORTAL = "1";
      GDK_DEBUG = "portals";
    };
  };
}
