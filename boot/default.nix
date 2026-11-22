# hearth's boot visuals: the Plymouth splash and the GRUB menu.
# Built from source: logos rendered from nixos-icons' SVG with resvg, GRUB
# fonts made from Inter with grub-mkfont.
{ pkgs }:
let
  inherit (pkgs) lib;
  py = pkgs.python3.withPackages (p: [ p.pillow ]);
  icons = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps";

  plymouth-theme-hearth = pkgs.stdenvNoCC.mkDerivation {
    pname = "plymouth-theme-hearth";
    version = "0.1.0";
    src = ./plymouth;
    nativeBuildInputs = [ py pkgs.resvg ];
    installPhase = ''
      runHook preInstall
      dir=$out/share/plymouth/themes/hearth
      mkdir -p $dir
      python3 mkassets.py $dir ${icons}/nix-snowflake.svg
      cp hearth.script $dir/
      substitute hearth.plymouth $dir/hearth.plymouth --subst-var out
      runHook postInstall
    '';
    meta = {
      description = "hearth's macOS-style Plymouth theme";
      platforms = lib.platforms.linux;
    };
  };

  # One package for every resolution: a theme per screen height plus
  # select-mode.cfg, which picks the largest mode the firmware has and its
  # theme (GRUB can't scale fonts, and its "auto" mode drops to 800x600 on a
  # 5K panel). See boot/grub/mktheme.py.
  grub-theme-hearth = pkgs.stdenvNoCC.mkDerivation {
    pname = "grub-theme-hearth";
    version = "0.2.0";
    src = ./.;
    nativeBuildInputs = [ py pkgs.resvg pkgs.grub2 ];
    installPhase = ''
      runHook preInstall
      python3 grub/mktheme.py $out \
        ${icons}/nix-snowflake.svg icons \
        ${pkgs.inter}/share/fonts/truetype/Inter.ttc \
        ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf
      runHook postInstall
    '';
    meta = {
      description = "hearth's GRUB theme, after macOS's Startup Manager";
      platforms = lib.platforms.linux;
    };
  };

in {
  inherit plymouth-theme-hearth grub-theme-hearth;
}
