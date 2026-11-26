# The system side of hearth's global menu (README "Global menu"), in one
# place:
#
#   imports = [ hearth.nixosModules.global-menu ];
#
# - The accessibility bus (AT-SPI). hearth reads every menu an app doesn't
#   export (☰ menus, Kirigami drawers, Firefox, Electron, Java Swing) over
#   it. Plasma used to turn it on; its removal left org.a11y.Bus missing.
# - The live bus's socket in a folder of its own (%t/at-spi-live): a test's
#   private session bus D-Bus-activates its own at-spi-bus-launcher, which
#   with the real XDG_RUNTIME_DIR wrote $XDG_RUNTIME_DIR/at-spi/bus_0 over
#   the live socket and died with the test, leaving every new AT-SPI client
#   with "connection refused" until a restart (2026-11-22). Clients find the
#   bus by asking org.a11y.Bus, never by path.
# - Flatpaks get an empty JAVA_TOOL_OPTIONS: the session loads hearth's
#   Java ATK bridge into every JVM (arbor/config.kdl), whose jar a sandbox
#   can't see. Java apps listed in hearth.globalMenu.javaFlatpaks get the
#   bridge instead (tested per app). Empty values go in the user's Flatpak
#   overrides (hearth.flatpakBlankEnv): nix-flatpak drops every empty value
#   from the system ones, so "" there never reached a Flatpak (2026-11-26).
#
# The rest lives with the session and the apps:
# - arbor/config.kdl (hearth's session config): GTK_MODULES (appmenu-gtk-
#   module, for plain GtkMenuBars; gail and atk-bridge, GTK 2 apps on
#   AT-SPI) and JAVA_TOOL_OPTIONS (the Java bridge).
# - Electron apps whose menus aren't exported need
#   `hearth.lib.globalMenu.electronFlags` in their wrappers: Electron only
#   builds its accessibility tree with it (or with a screen reader).
self:
{ config, lib, options, pkgs, ... }:
let
  jaw = "/run/current-system/sw/lib/java-atk-wrapper";
  javaToolOptions = "-Xbootclasspath/a:${jaw}/java-atk-wrapper.jar"
    + " -Djavax.accessibility.assistive_technologies=org.GNOME.Accessibility.AtkWrapper";
in
{
  # Java apps installed as Flatpaks that get the Java bridge (and so a
  # global menu): the bridge works inside Flatpaks (it uses the runtime's
  # own GLib/ATK there), but each app is added only once tested, as Ben
  # decided (2026-11-24). They see the bridge's folder read-only.
  options.hearth.globalMenu.javaFlatpaks = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "org.jdownloader.JDownloader" ];
    description = "Flatpak ids of Java apps that load hearth's Java accessibility bridge.";
  };

  # Session variables Flatpaks get empty: ones naming things a sandbox
  # can't see. Set in the user's global Flatpak overrides at login (an
  # app's own overrides still win). Taking one off the list leaves it
  # blank until `flatpak override --user --unset-env=NAME`.
  options.hearth.flatpakBlankEnv = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "QT_QUICK_CONTROLS_STYLE" ];
    description = "Environment variables set empty for every Flatpak (user overrides).";
  };

  config = lib.mkMerge [
    {
      services.gnome.at-spi2-core.enable = true;
      systemd.user.services.at-spi-dbus-bus.serviceConfig = {
        RuntimeDirectory = "at-spi-live";
        RuntimeDirectoryMode = "0700";
        Environment = "XDG_RUNTIME_DIR=%t/at-spi-live";
      };
    }
    { hearth.flatpakBlankEnv = [ "JAVA_TOOL_OPTIONS" ]; }
    (lib.mkIf (config.services.flatpak.enable && config.hearth.flatpakBlankEnv != [ ]) {
      systemd.user.services.hearth-flatpak-blank-env = {
        description = "Blank session variables Flatpaks can't use (user Flatpak overrides)";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.flatpak}/bin/flatpak override --user "
            + lib.concatMapStringsSep " " (v: "--env=${v}=") config.hearth.flatpakBlankEnv;
        };
      };
    })
    (lib.optionalAttrs (options ? services.flatpak.overrides) {
      services.flatpak.overrides = {
        # Every Flatpak may register its window's menu with hearth's
        # registrar: Electron, Chromium and Qt apps export dbusmenu menus
        # but most manifests don't ask for this name (the survey's
        # flatpak+registrar lever: about 30 Flathub apps, 2026-11-25).
        global."Session Bus Policy"."com.canonical.AppMenu.Registrar" = "talk";
      } // lib.genAttrs config.hearth.globalMenu.javaFlatpaks (_: {
        Context.filesystems = [ "${jaw}:ro" ];
        Environment.JAVA_TOOL_OPTIONS = javaToolOptions;
        # Read by the java launcher too; kept by launchers that strip
        # JAVA_TOOL_OPTIONS when they restart themselves (TL).
        Environment.JDK_JAVA_OPTIONS = javaToolOptions;
      });
    })
  ];
}
