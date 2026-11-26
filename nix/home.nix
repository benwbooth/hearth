self:
# The Hearth desktop's per-user glue (home-manager): `hearth.home`.
#
# - arbor's config: the real one is hearth's arbor/config.kdl, installed
#   live into ~/.config/hearth/arbor/ (by devloop on Ben's machine, with
#   every new hearth; validated first, arbor reloads it by itself), so
#   desktop fixes need no rebuild. ~/.config/arbor/config.kdl only includes
#   it, and the packaged copy seeds it when it's missing (a fresh install).
# - The GTK/Chromium UI font (Inter, as hearth's Qt apps use; their menus
#   too, which read it from GTK). On Wayland GTK takes it from dconf (also
#   through the portal), not settings.ini. Light/dark stays with
#   hearth-color-scheme.
# - Vicinae (the launcher), themed: our settings live in an imported file so
#   settings.json stays writable for Vicinae's own settings window.
# - satty (the screenshot editor hearth's Print overlay pipes captures into):
#   Enter copies and closes, Ctrl+S saves, Esc quits.
# - hyprlock (the lock screen fallback, nixosModules.session): Breeze Dark.
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.home;
  hearth = self.packages.${pkgs.stdenv.hostPlatform.system}.hearth;
in
{
  options.hearth.home = {
    enable = lib.mkEnableOption "the Hearth desktop's per-user settings (arbor config, launcher, screenshot editor, lock screen, GTK font)";
    fontName = lib.mkOption {
      type = lib.types.str;
      default = "Inter 10.5";
      description = "GTK and Chromium/Electron UI font (10.5 pt is hearth's menus' 14.1 px).";
    };
    screenshotDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Pictures/Screenshots";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/Pictures/Screenshots"'';
      description = "Where satty saves (Ctrl+S).";
    };
  };

  config = lib.mkIf cfg.enable {
    dconf.settings."org/gnome/desktop/interface".font-name = cfg.fontName;

    xdg.configFile."arbor/config.kdl".text = ''
      // Written by hearth.home (hearth nix/home.nix). The config itself is
      // hearth's arbor/config.kdl, installed live into ~/.config/hearth/arbor/.
      include "~/.config/hearth/arbor/config.kdl"
    '';
    home.activation.hearthArborConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      d="$HOME/.config/hearth/arbor"
      if [ ! -e "$d/config.kdl" ]; then
        mkdir -p "$d"
        cp ${hearth}/share/hearth/arbor/config.kdl ${hearth}/share/hearth/arbor/hearth-layer-rules.kdl "$d/"
        chmod u+w "$d"/*.kdl
      fi
    '';

    xdg.dataFile."vicinae/themes/breeze-dark.toml".source = "${hearth}/share/hearth/vicinae/breeze-dark.toml";
    xdg.configFile."vicinae/hearth.json".source = "${hearth}/share/hearth/vicinae/hearth.json";
    home.activation.vicinaeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      f="$HOME/.config/vicinae/settings.json"
      if [ ! -e "$f" ]; then
        mkdir -p "$(dirname "$f")"
        printf '{\n  "imports": ["./hearth.json"]\n}\n' > "$f"
      fi
    '';

    xdg.configFile."satty/config.toml".text = ''
      [general]
      early-exit = true
      initial-tool = "arrow"
      copy-command = "wl-copy"
      output-filename = "${cfg.screenshotDir}/Screenshot_%Y%m%d_%H%M%S.png"
      actions-on-enter = ["save-to-clipboard"]
      actions-on-escape = ["exit"]
      corner-roundness = 4
      [font]
      family = "Noto Sans"
    '';

    xdg.configFile."hypr/hyprlock.conf".text = ''
      general {
        hide_cursor = true
        grace = 0
      }
      background {
        monitor =
        color = rgb(202326)
        blur_passes = 0
      }
      label {
        monitor =
        text = $TIME
        color = rgb(fcfcfc)
        font_size = 96
        font_family = Noto Sans
        position = 0, 220
        halign = center
        valign = center
      }
      label {
        monitor =
        text = cmd[update:60000] date '+%A, %B %-d'
        color = rgb(a1a9b1)
        font_size = 22
        font_family = Noto Sans
        position = 0, 120
        halign = center
        valign = center
      }
      input-field {
        monitor =
        size = 360, 52
        outline_thickness = 2
        outer_color = rgb(3daee9)
        inner_color = rgb(31363b)
        font_color = rgb(fcfcfc)
        check_color = rgb(27ae60)
        fail_color = rgb(da4453)
        placeholder_text = Password
        fade_on_empty = false
        rounding = 8
        position = 0, -40
        halign = center
        valign = center
      }
    '';
  };
}
