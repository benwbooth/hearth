self:
# The Hearth look for other apps (README "Appearance"):
#
#   imports = [ hearth.nixosModules.appearance ];
#   hearth.appearance = { enable = true; qtStyle.package = ...; gtkTheme.package = ...; };
#
# hearth's light/dark helper (hearth-color-scheme) writes each toolkit's
# settings; this installs what they name and points the toolkits at them.
# - Qt: qt5ct/qt6ct as the platform theme (qt6ct answers to "qt5ct" too),
#   session-wide so apps D-Bus or the desktop start get it as well. Without
#   a platform theme outside Plasma, Qt apps had plain hicolor icons and Qt's
#   own palette and font (2026-11-25). Qt Quick apps (Kirigami ones too)
#   get hearth-qt-style's org.hearth.desktop Controls style; Qt 5 apps don't
#   find it and keep their default.
# - GTK 2/3/4: hearth-gtk-theme (Hearth, Hearth-dark); GTK 2's part uses
#   the adwaita engine from gnome-themes-extra.
# - Pointers: Adwaita (hearth's default) everywhere, also where an app or
#   the login screen has no setting of its own (Plasma made breeze_cursors
#   the fallback); apple-cursor for Settings > Appearance > Pointer.
# - Inter: hearth's font when SF Pro isn't installed; the menus and title
#   bars of Hearth's own Qt apps use it too, so it's installed for all.
# - Flatpaks: Qt ones use the runtime's KDE platform theme, which reads
#   kdeglobals through the Settings portal (hearth-portal serves it:
#   hearth's palette, Inter, widgetStyle=Hearth; hearth-qt-style's
#   flatpak/build.sh installs org.kde.KStyle.Hearth); the session's qt5ct
#   is in no runtime. QT_QUICK_CONTROLS_STYLE names a QML module a Flatpak
#   can't see unless its runtime has the extension, and then Qt Quick
#   Flatpaks failed to load: it's blank for them (hearth.flatpakBlankEnv,
#   nixosModules.global-menu); build.sh sets it per app where the runtime
#   has it.
{ config, lib, options, pkgs, ... }:
let cfg = config.hearth.appearance; in
{
  options.hearth.appearance = {
    enable = lib.mkEnableOption "the Hearth look for Qt, GTK and Flatpak apps";
    qtStyle.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "inputs.hearth-qt-style.packages.\${system}.default";
      description = "hearth-qt-style: the Hearth widget style for Qt 5 and 6 (and its Qt Quick Controls style).";
    };
    gtkTheme.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "inputs.hearth-gtk-theme.packages.\${system}.default";
      description = "hearth-gtk-theme: the Hearth GTK 2/3/4 theme.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages =
        lib.optional (cfg.qtStyle.package != null) cfg.qtStyle.package
        ++ lib.optional (cfg.gtkTheme.package != null) cfg.gtkTheme.package
        ++ [
          pkgs.adwaita-icon-theme # Adwaita pointer (data only, no GNOME services)
          pkgs.gnome-themes-extra # GTK 2's adwaita engine
          pkgs.apple-cursor
        ];
      xdg.icons.fallbackCursorThemes = lib.mkForce [ "Adwaita" ];
      fonts.packages = [ pkgs.inter ];
      qt = {
        enable = true;
        platformTheme = "qt5ct";
      };
      environment.sessionVariables = {
        QT_QPA_PLATFORMTHEME = "qt5ct";
      } // lib.optionalAttrs (cfg.qtStyle.package != null) {
        QT_QUICK_CONTROLS_STYLE = "org.hearth.desktop";
      };
    }
    (lib.optionalAttrs (options ? services.flatpak.overrides) {
      # The portal's platform theme: Qt Flatpaks' file dialogs are then the
      # desktop's (grove's picker through the FileChooser portal); with
      # "kde" the KDE theme drew its own (SpeechNote's "Import from a
      # file"). Ben, 2026-11-26: the desktop's dialog, always.
      services.flatpak.overrides.global.Environment.QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
    })
    (lib.optionalAttrs (options ? hearth.flatpakBlankEnv) {
      hearth.flatpakBlankEnv = lib.mkIf (cfg.qtStyle.package != null) [ "QT_QUICK_CONTROLS_STYLE" ];
    })
  ]);
}
