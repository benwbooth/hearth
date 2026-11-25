# appimage-run for the survey's AppImage source: nixos-unstable's (glibc
# 2.44: AppImages built on new distros need GLIBC_2.43) with the libraries
# AppImages most often expect from the host and stable's FHS env lacks
# (tallied from the survey's "cannot open shared object" logs, 2026-11-25).
# The same override would fix them for programs.appimage on the desktop.
#
#   nix build -f appimage-run.nix -o ~/.cache/hearth-menu-survey/roots/appimage-run
{ rev ? "0bb8272318b4ca41bf0edc6224df3e3e3046b70d" }:  # /etc/nixos's nixpkgs-unstable
let
  pkgs = (builtins.getFlake "github:NixOS/nixpkgs/${rev}").legacyPackages.x86_64-linux;
  # Each by name, skipped when this nixpkgs lacks or has removed it.
  pick = p: names: builtins.concatMap (n:
    let r = builtins.tryEval (let v = p.${n} or (p.xorg.${n} or null); in
      if v == null then null else builtins.seq v.outPath v);
    in if r.success && r.value != null then [ r.value ] else [ ]) names;
in
pkgs.appimage-run.override {
  extraPkgs = p: pick p [
    "libepoxy" "libxshmfence" "zstd" "libxcrypt-legacy" "libva" "elfutils" "lz4"
    "webkitgtk_4_1" "webkitgtk_6_0" "nghttp2" "keybinder3" "gtk2" "glibmm_2_4" "libpng"
    "libcdio" "avahi" "mpv-unwrapped"
    # Qt's xcb platform plugin (Qt 5 and 6 AppImages that bundle only xcb)
    "xcb-util-cursor" "xcbutilwm" "xcbutilimage" "xcbutilkeysyms" "xcbutilrenderutil" "libxkbcommon"
  ];
}
