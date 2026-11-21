{
  description = "hearth: a Quickshell desktop shell for Hyprland";

  # /etc/nixos sets `inputs.nixpkgs.follows`, so Quickshell links the same Qt
  # as Plasma's platform theme and the KDE apps; a second Qt would fail to load
  # the `kde` platform theme plugin.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.quickshell-src = {
    url = "https://git.outfoxxed.me/quickshell/quickshell/archive/refs/tags/v0.3.2.tar.gz";
    flake = false;
  };

  outputs = { self, nixpkgs, quickshell-src }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = pkgs.lib;

    # 26.05 ships 0.3.0; 0.3.2 adds the NativeTextRendering pragma.
    quickshell = pkgs.quickshell.overrideAttrs (_: {
      version = "0.3.2";
      src = quickshell-src;
    });

    python = pkgs.python3.withPackages (p: [ p.dbus-python p.pygobject3 ]);

    # Everything the shell's widgets shell out to.
    runtimeDeps = with pkgs; [
      quickshell
      wl-clipboard vicinae
      ddcutil hyprsunset gammastep
      udisks networkmanager
      curl jq libnotify xdg-utils pciutils cups
      wlogout hyprpaper swaynotificationcenter grim satty
      pipewire wireplumber
      systemd procps coreutils gnugrep gawk util-linux iproute2
      swayidle
      python
    ];

    # The `kde` platform theme picks the org.kde.desktop Controls style, which
    # imports Kirigami. Plasma's session provides it; outside Plasma
    # (Hyprland) nothing does, so controls fail to load without this.
    qmlPath = lib.makeSearchPath "lib/qt-6/qml" (with pkgs.kdePackages; [
      kirigami.unwrapped qqc2-desktop-style sonnet kitemmodels
    ]);

    # Inter: the shell font when Apple's SF Pro isn't installed (SF Pro is
    # Apple-licensed, so never shipped). Theme.qml loads it from here with a
    # FontLoader, so it works without a system-wide install.
    fontDir = "${pkgs.inter}/share/fonts/truetype";

    hearth = pkgs.stdenvNoCC.mkDerivation {
      pname = "hearth";
      version = "0.1.0";
      src = lib.cleanSource ./.;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/hearth $out/bin
        cp -r shell helpers hypr vicinae swaync $out/share/hearth/
        chmod +x $out/share/hearth/helpers/*
        patchShebangs $out/share/hearth/helpers
        # Apps launched from the dock inherit the bar's working directory;
        # start in $HOME so a bar run from a since-deleted directory doesn't
        # hand every app a dangling cwd.
        makeWrapper ${quickshell}/bin/quickshell $out/bin/hearth \
          --run 'cd "$HOME"' \
          --add-flags "-p $out/share/hearth/shell" \
          --prefix PATH : ${lib.makeBinPath runtimeDeps}:$out/share/hearth/helpers \
          --prefix QML_IMPORT_PATH : ${qmlPath} \
          --set-default HEARTH_FONT_DIR ${fontDir} \
          --set-default HEARTH_XKB_RULES ${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.lst
        # Talk to the running hearth whichever build started it: quickshell
        # matches instances by config path, so after a rebuild (or a bar
        # started from another build) `-p` finds nothing and every keybind
        # through hearth-ipc silently fails. Pick the newest hearth by pid.
        cat > $out/bin/hearth-ipc <<EOF
        #!${pkgs.runtimeShell}
        pid=\$(${pkgs.procps}/bin/pgrep -nf 'quickshell -p /nix/store/[^ ]*-hearth-[^ ]*/share/hearth/shell')
        if [ -n "\$pid" ]; then exec ${quickshell}/bin/quickshell ipc --pid "\$pid" "\$@"; fi
        exec ${quickshell}/bin/quickshell ipc -p $out/share/hearth/shell "\$@"
        EOF
        chmod +x $out/bin/hearth-ipc
        runHook postInstall
      '';
      meta.mainProgram = "hearth";
    };
  in {
    packages.${system} = {
      default = hearth;
      inherit hearth quickshell;
    };

    # `nix develop`, then `quickshell -p shell` runs straight from the
    # checkout and hot-reloads on every save.
    devShells.${system}.default = pkgs.mkShell {
      packages = runtimeDeps ++ [ pkgs.kdePackages.qtdeclarative ];
      shellHook = ''
        export PATH="$PWD/helpers:$PATH"
        export HEARTH_FONT_DIR=''${HEARTH_FONT_DIR:-${fontDir}}
      '';
    };
  };
}
