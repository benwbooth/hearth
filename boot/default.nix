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

  # scale = gfxmode height / 1600. GRUB can't scale fonts, so sizes are baked
  # for one resolution: 1.0 for 3840x1600, 1.35 for 5120x2160.
  mkGrubTheme = { scale ? 1.0, suffix ? "" }: pkgs.stdenvNoCC.mkDerivation {
    pname = "grub-theme-hearth${suffix}";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [ py pkgs.resvg pkgs.grub2 ];
    installPhase = ''
      runHook preInstall
      python3 grub/mktheme.py $out ${toString scale} \
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
  inherit plymouth-theme-hearth mkGrubTheme;
  grub-theme-hearth = mkGrubTheme { };
  grub-theme-hearth-5k = mkGrubTheme { scale = 1.35; suffix = "-5k"; };
}
