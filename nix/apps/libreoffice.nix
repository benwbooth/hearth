self:
# LibreOffice's global menu in the Tabbed (notebookbar) interfaces.
#
# With a global menu (hearth-appmenu owns com.canonical.AppMenu.Registrar)
# LibreOffice's GTK menu bar is the GMenuModel it exports, and it can't
# hide that, so a mode without a menu bar "hides" it by emptying the
# exported menu (vcl/unx/gtk3/gtksalmenu.cxx, GtkSalMenu::ShowMenuBar):
# the bar showed the menus for a moment, then the app name and Window
# alone. Every notebookbar mode (Tabbed, Groupedbar, ...) has HasMenubar
# false. This turns it on, in a configuration layer of its own between
# LibreOffice's defaults and the user's settings (which still win): the
# ribbon stays in the window and the menus are in the menu bar.
#
# The layer is added through the CONFIGURATION_LAYERS bootstrap variable,
# which LibreOffice also reads from the environment: its own value from
# fundamentalrc with one more `xcsxcu:` layer after the shipped registry.
#
# The desktop's file dialog (grove's, through the FileChooser portal):
# LibreOffice's GTK backend makes and runs its own GtkFileChooserDialog,
# which GTK 3 never sends to the portal (its Qt backend forces Qt's own
# dialog too). gtk3-portal-chooser.c, preloaded, runs it as a portal
# dialog instead, its check boxes and lists (Save with password, Edit
# filter settings, Keep current format, Version...) as the portal's
# "choices", and gives LibreOffice the answers. Nothing of LibreOffice is
# rebuilt: a small library and the launcher's environment.
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.apps.libreoffice;
  modes = {
    Writer = [ "Single" "Sidebar" "Tabbed" "TabbedCompact" "GroupedbarCompact" "GroupedbarFull" "ContextualSingle" "ContextualGroups" ];
    Calc = [ "Single" "Sidebar" "Tabbed" "TabbedCompact" "GroupedbarCompact" "GroupedbarFull" "ContextualGroups" ];
    Impress = [ "Single" "Tabbed" "TabbedCompact" "GroupedbarCompact" "GroupedbarFull" "ContextualSingle" "ContextualGroups" ];
    Draw = [ "Tabbed" "TabbedCompact" "GroupedbarCompact" "ContextualSingle" ];
  };
  # (Only modes LibreOffice defines: `fuse` on a missing set member would
  # add a half-made one.)
  layer = pkgs.writeTextDir "data/org/openoffice/Office/UI/ToolbarMode.xcu" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <oor:component-data xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" oor:name="ToolbarMode" oor:package="org.openoffice.Office.UI">
     <node oor:name="Applications">
    ${lib.concatStrings (lib.mapAttrsToList (app: ms: ''
      <node oor:name="${app}"><node oor:name="Modes">
    ${lib.concatMapStrings (m: ''
         <node oor:name="${m}" oor:op="fuse"><prop oor:name="HasMenubar"><value>true</value></prop></node>
    '') ms}  </node></node>
    '') modes)} </node>
    </oor:component-data>
  '';
  chooser = pkgs.stdenv.mkDerivation {
    pname = "hearth-gtk3-portal-chooser";
    version = "0.1.0";
    src = ./gtk3-portal-chooser.c;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.gtk3 ];
    # (GTK is looked up at run time; only GLib/GIO are linked, which every
    # process of a GTK app has anyway.)
    buildPhase = ''
      $CC -shared -fPIC -O2 -Wall -Wno-deprecated-declarations -o libgtk3-portal-chooser.so $src \
        $(pkg-config --cflags gtk+-3.0) $(pkg-config --libs gio-2.0) -ldl
    '';
    installPhase = "install -Dm755 libgtk3-portal-chooser.so $out/lib/libgtk3-portal-chooser.so";
  };
  wrapped = pkgs.symlinkJoin {
    name = "${cfg.package.name}-hearth";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rc=$(readlink -f ${cfg.package}/lib/libreoffice/program/fundamentalrc)
      layers=$(sed -n 's/^CONFIGURATION_LAYERS=//p' "$rc")
      shipped='res:''${BRAND_BASE_DIR}/share/registry'
      case "$layers" in *"$shipped"*) ;; *) echo "fundamentalrc: no '$shipped' layer" >&2; exit 1 ;; esac
      layers=''${layers/"$shipped"/"$shipped xcsxcu:file://${layer}"}
      for f in $out/bin/*; do
        wrapProgram "$f" --set-default CONFIGURATION_LAYERS "$layers" \
          --prefix LD_PRELOAD : ${chooser}/lib/libgtk3-portal-chooser.so \
          --set-default GTK_USE_PORTAL 1
      done
    '';
  };
in
{
  options.hearth.apps.libreoffice = {
    enable = lib.mkEnableOption "LibreOffice, adjusted for the Hearth desktop (global menu in the Tabbed interfaces, the desktop's file dialog)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.libreoffice;
      defaultText = lib.literalExpression "pkgs.libreoffice";
      description = "The LibreOffice package to adjust.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ wrapped ];
  };
}
