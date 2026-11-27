self:
# AppImages on the Hearth desktop: appimage-run, plus the AppImages it
# can't open.
#
# uruntime AppImages (pkgforge's "anylinux" builds: VSCodium, RSS Guard,
# the Eden Switch emulator...) carry a DwarFS image where appimage-run
# expects squashfs ("Can't find a valid SQUASHFS superblock"), so they never
# started. They bundle their own loader and libraries (sharun), so they need
# no FHS environment: the launcher unpacks one once (dwarfsextract, into
# ~/.cache/appimage-run-dwarfs, by size and date) and runs its AppRun.
# Everything else goes to appimage-run as before. It's the binfmt
# interpreter too, so double-clicked AppImages and launchers that call
# `appimage-run` (Lunchpail) both get it.
#
# Their fix-namespaces hook tests user namespaces with `unshare -r
# /bin/true`; NixOS has no /bin/true, the test fails and the hook opens an
# xterm about Ubuntu's restriction instead of the app. /bin/true is linked
# to coreutils' for it.
{ config, lib, pkgs, ... }:
let
  cfg = config.hearth.apps.appimage;
  launcher = pkgs.writeShellScriptBin "appimage-run" ''
    f=''${1-}
    off=
    if [ -f "$f" ] && [ "$(${pkgs.coreutils}/bin/head -c 4 "$f" | ${pkgs.coreutils}/bin/od -An -c | ${pkgs.coreutils}/bin/tr -d ' ')" = "177ELF" ]; then
      # The image starts where the ELF runtime ends: its section headers' end.
      shoff=$(${pkgs.coreutils}/bin/od -An -t u8 -j 40 -N 8 "$f" | ${pkgs.coreutils}/bin/tr -d ' ')
      read -r shentsize shnum < <(${pkgs.coreutils}/bin/od -An -t u2 -j 58 -N 4 "$f")
      end=$((shoff + shentsize * shnum))
      if [ "$(${pkgs.coreutils}/bin/dd if="$f" bs=1 skip="$end" count=6 status=none)" = "DWARFS" ]; then
        off=$end
      fi
    fi
    if [ -z "$off" ]; then
      exec ${lib.getExe cfg.package} "$@"
    fi
    shift
    key=$(${pkgs.coreutils}/bin/basename "$f")-$(${pkgs.coreutils}/bin/stat -c '%s-%Y' "$f")
    dir=''${XDG_CACHE_HOME:-$HOME/.cache}/appimage-run-dwarfs/$key
    if [ ! -x "$dir/AppRun" ]; then
      ${pkgs.coreutils}/bin/rm -rf "$dir.tmp"
      ${pkgs.coreutils}/bin/mkdir -p "$dir.tmp"
      ${pkgs.dwarfs}/bin/dwarfsextract -i "$f" -o "$dir.tmp" --image-offset="$off" >/dev/null || exit 1
      ${pkgs.coreutils}/bin/rm -rf "$dir"
      ${pkgs.coreutils}/bin/mv "$dir.tmp" "$dir"
    fi
    APPIMAGE=$(${pkgs.coreutils}/bin/realpath "$f")
    export APPIMAGE APPDIR="$dir" ARGV0="$f"
    exec "$dir/AppRun" "$@"
  '';
in
{
  options.hearth.apps.appimage = {
    enable = lib.mkEnableOption "AppImages on the Hearth desktop (DwarFS AppImages too)";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.appimage-run;
      defaultText = lib.literalExpression "pkgs.appimage-run";
      description = "The appimage-run that opens squashfs AppImages.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.appimage = {
      enable = true;
      package = lib.hiPrio launcher;  # over a plain appimage-run in systemPackages
    };
    systemd.tmpfiles.rules = [ "L+ /bin/true - - - - ${pkgs.coreutils}/bin/true" ];
  };
}
