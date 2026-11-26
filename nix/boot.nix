# hearth's boot visuals (README "Boot"): the GRUB menu and the Plymouth
# splash.
#
#   imports = [ hearth.nixosModules.boot ];
#   hearth.boot.enable = true;
#
# Leave boot.loader.grub.gfxmodeEfi and the kernel's video= unset: the theme
# picks the largest mode the firmware has (select-mode.cfg) and Linux keeps
# it, so the menu, the splash and the desktop all run at the panel's own
# resolution without a mode switch.
self:
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.boot;
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
in {
  options.hearth.boot = {
    enable = lib.mkEnableOption "hearth's GRUB menu and Plymouth splash";
    grub = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use hearth's GRUB theme (when GRUB is the bootloader).";
    };
    plymouth = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use hearth's Plymouth splash.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.grub {
      boot.loader.grub = {
        theme = packages.grub-theme-hearth;
        splashImage = null;
        # NixOS sets gfxmode and turns on gfxterm only when a font is set; the
        # theme's script does both itself, once, with the mode it found.
        font = null;
        # macOS-style: no menu unless Esc, F4 or Shift is pressed while GRUB
        # waits (boot.loader.timeout seconds); the screen shows the boot
        # splash meanwhile.
        timeoutStyle = lib.mkDefault "hidden";
        extraConfig = ''
          regexp --set=1:hearth_theme_dir '^(.*)/[^/]*$' "$theme"
          source "$hearth_theme_dir/select-mode.cfg"
        '';
      };
    })
    (lib.mkIf cfg.plymouth {
      boot.plymouth = {
        enable = true;
        theme = "hearth";
        themePackages = [ packages.plymouth-theme-hearth ];
        font = "${pkgs.inter}/share/fonts/truetype/InterVariable.ttf";
        # The art is pre-rendered per size, so no scaling. UseSimpledrm:
        # draw on the firmware's framebuffer (already at the panel's mode)
        # as soon as the kernel starts, instead of leaving GRUB's last
        # screen up until the GPU driver loads.
        extraConfig = ''
          ShowDelay=0
          DeviceScale=1
          UseSimpledrm=1
        '';
      };
    })
  ]);
}
