# appmenu-gtk-module (vala-panel-appmenu, ex unity-gtk-module): loaded into
# GTK 3 apps with GTK_MODULES=appmenu-gtk-module, it turns plain GtkMenuBars
# (apps that aren't GtkApplications with a GMenuModel menu bar: Emacs,
# Inkscape's older menus, virt-manager, meld...) into a GMenuModel on the
# session bus and hides them in the window. On Wayland it hands the address
# to the compositor through gtk_shell1 set_dbus_properties (arbor implements
# it; hearth's menu bar reads it); on X11 it sets the _GTK_* window
# properties.
#
# Built from the same source as nixpkgs' appmenu-glib-translator, with four
# changes for use outside Ubuntu/Budgie:
# - Plain windows register after realize (see `patches`), so Wayland works.
# - Its settings schema is looked up in its own directory first, so apps
#   whose XDG_DATA_DIRS lack it don't abort in g_settings_new.
# - That copy defaults `run-on-wayland` to true (upstream: false).
# - The module and its parser library carry no DT_NEEDED on GTK/GLib: they
#   use the host app's (always loaded before a GTK module), so an app built
#   against another nixpkgs never ends up with two GTKs in one process.
# Built twice: for GTK 3 (the default) and GTK 2 (`gtkVersion = "2"`, with
# gtk2: Pidgin, Sublime Text, Gwyddion... X11-only, so the menu reaches
# hearth through the _GTK_* window properties). GTK_MODULES names both; each
# GTK loads its own from GTK_PATH's gtk-2.0 or gtk-3.0.
{ lib, stdenv, meson, ninja, pkg-config, glib, gtk3, patchelf, appmenu-glib-translator
, gtk ? gtk3, gtkVersion ? "3" }:

let gtkdir = "gtk-${gtkVersion}.0"; in
stdenv.mkDerivation {
  pname = "appmenu-gtk${lib.optionalString (gtkVersion != "3") gtkVersion}-module";
  version = appmenu-glib-translator.version;
  src = appmenu-glib-translator.src;
  sourceRoot = "${appmenu-glib-translator.src.name}/subprojects/appmenu-gtk-module";

  nativeBuildInputs = [ meson ninja pkg-config glib patchelf ];
  buildInputs = [ glib gtk ];
  mesonFlags = [ "-Dgtk=${gtkVersion}" ];

  # Upstream registers a plain window's menu before the window is realized,
  # when it has no GdkWindow yet, so on Wayland set_dbus_properties fails
  # ("GDK_IS_WAYLAND_WINDOW (window) failed") and nothing is exported.
  patches = [ ./appmenu-gtk-module-wayland-realize.patch ];

  postPatch = ''
    substituteInPlace src/${gtkdir}/meson.build \
      --replace-fail "join_paths(gtk${gtkVersion}.get_variable(pkgconfig:'libdir'),'${gtkdir}','modules')" \
                     "join_paths(get_option('libdir'),'${gtkdir}','modules')"
    # No systemd user unit (it only sets GTK_MODULES in the systemd env).
    substituteInPlace data/meson.build --replace-fail "if systemd.found()" "if false"
    cat >> src/consts.h <<EOF
    #include <gio/gio.h>
    static inline GSettings *appmenu_settings_new(void)
    {
      GSettingsSchemaSource *src = g_settings_schema_source_new_from_directory(
          "$out/share/appmenu-gtk-module/schemas", g_settings_schema_source_get_default(), FALSE, NULL);
      GSettingsSchema *schema = src ? g_settings_schema_source_lookup(src, UNITY_GTK_MODULE_SCHEMA, TRUE) : NULL;
      GSettings *s = schema ? g_settings_new_full(schema, NULL, NULL) : NULL;
      if (schema) g_settings_schema_unref(schema);
      if (src) g_settings_schema_source_unref(src);
      return s;
    }
    EOF
    sed -i 's/g_settings_new(UNITY_GTK_MODULE_SCHEMA)/appmenu_settings_new()/' src/support.c src/blacklist.c
    grep -q '#include "consts.h"' src/blacklist.c || sed -i '0,/#include <gtk\/gtk.h>/s//#include <gtk\/gtk.h>\n#include "consts.h"/' src/blacklist.c
  '';

  postInstall = ''
    d=$out/share/appmenu-gtk-module/schemas
    mkdir -p $d
    cp ${appmenu-glib-translator.src}/subprojects/appmenu-gtk-module/data/org.appmenu.gtk-module.gschema.xml $d/
    cat > $d/90_hearth.gschema.override <<EOF
    [org.appmenu.gtk-module]
    run-on-wayland=true
    EOF
    glib-compile-schemas $d
  '';

  postFixup = ''
    for f in $out/lib/${gtkdir}/modules/libappmenu-gtk-module.so $out/lib/libappmenu-gtk${gtkVersion}-parser.so.*.*; do
      [ -L "$f" ] && continue
      for n in $(patchelf --print-needed "$f"); do
        case "$n" in
          libgtk-3.so*|libgdk-3.so*|libgtk-x11-2.0.so*|libgdk-x11-2.0.so*|libglib-2.0.so*|libgobject-2.0.so*|libgio-2.0.so*|libgmodule-2.0.so*|libpango*|libcairo*|libgdk_pixbuf*|libharfbuzz*|libatk*|libX11*|libwayland*)
            patchelf --remove-needed "$n" "$f" ;;
        esac
      done
    done
  '';

  meta = {
    description = "GTK module that exports GtkMenuBars over D-Bus for global menus";
    license = lib.licenses.lgpl3Plus;
    platforms = lib.platforms.linux;
  };
}
