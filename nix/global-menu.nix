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
# - Flatpaks get an empty JAVA_TOOL_OPTIONS (with nix-flatpak): the session
#   loads hearth's Java ATK bridge into every JVM (arbor/config.kdl), whose
#   jar a sandbox can't see, and Java ends a Swing app whose assistive
#   technology can't load.
#
# The rest lives with the session and the apps:
# - arbor/config.kdl (hearth's session config): GTK_MODULES (appmenu-gtk-
#   module, for plain GtkMenuBars) and JAVA_TOOL_OPTIONS (the Java bridge).
# - Electron apps whose menus aren't exported need
#   `hearth.lib.globalMenu.electronFlags` in their wrappers: Electron only
#   builds its accessibility tree with it (or with a screen reader).
self:
{ lib, options, ... }:
{
  config = lib.mkMerge [
    {
      services.gnome.at-spi2-core.enable = true;
      systemd.user.services.at-spi-dbus-bus.serviceConfig = {
        RuntimeDirectory = "at-spi-live";
        RuntimeDirectoryMode = "0700";
        Environment = "XDG_RUNTIME_DIR=%t/at-spi-live";
      };
    }
    (lib.optionalAttrs (options ? services.flatpak.overrides) {
      services.flatpak.overrides.global.Environment.JAVA_TOOL_OPTIONS = "";
    })
  ];
}
