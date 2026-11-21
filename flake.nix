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
      wl-clipboard cliphist vicinae
      ddcutil hyprsunset gammastep
      udisks networkmanager
      curl jq libnotify xdg-utils pciutils cups
      wlogout hyprpaper swaynotificationcenter grim satty
      wf-recorder vips
      pipewire wireplumber
      systemd procps coreutils gnugrep gawk util-linux iproute2
      swayidle
      python
      xprop   # hearth-appmenu: X11 windows' menu properties (xwayland-satellite)
      # Wallpaper engine (helpers/hearth-wallpaper, desktop/Background.qml):
      # Wallpaper Engine projects, macOS .heic dynamic desktops, video
      # posters, Shadertoy compiles (qsb), API keys in the Secret Service.
      linux-wallpaperengine libheif.bin ffmpeg-headless
      kdePackages.qtshadertools libsecret
    ];

    # The `kde` platform theme picks the org.kde.desktop Controls style, which
    # imports Kirigami. Plasma's session provides it; outside Plasma
    # (Hyprland) nothing does, so controls fail to load without this.
    qmlPath = lib.makeSearchPath "lib/qt-6/qml" (with pkgs.kdePackages; [
      kirigami.unwrapped qqc2-desktop-style sonnet kitemmodels
      qtmultimedia
    ]);
    # QtMultimedia's FFmpeg backend (video wallpapers, VA-API decoding).
    pluginPath = "${pkgs.kdePackages.qtmultimedia}/lib/qt-6/plugins";
    # GNOME's light/dark wallpaper pairs, listed under Dynamic.
    backgroundDirs = "${pkgs.gnome-backgrounds}/share/gnome-background-properties";

    # Inter: the shell font when Apple's SF Pro isn't installed (SF Pro is
    # Apple-licensed, so never shipped). Theme.qml loads it from here with a
    # FontLoader, so it works without a system-wide install.
    fontDir = "${pkgs.inter}/share/fonts/truetype";

    # Global menus for plain GtkMenuBars (README "Global menu").
    appmenu-gtk-module = pkgs.callPackage ./nix/appmenu-gtk-module.nix { };

    hearth = pkgs.stdenvNoCC.mkDerivation {
      pname = "hearth";
      version = "0.1.0";
      src = lib.cleanSource ./.;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/hearth $out/bin
        cp -r shell helpers hypr vicinae swaync $out/share/hearth/
        # Built-in user pictures (avatars/CREDITS.md), for Settings > Users &
        # Accounts and the login screen: $out/share/hearth/avatars.
        cp -r avatars $out/share/hearth/
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
          --prefix QT_PLUGIN_PATH : ${pluginPath} \
          --set-default HEARTH_BACKGROUND_DIRS ${backgroundDirs} \
          --set-default HEARTH_AVATAR_DIR $out/share/hearth/avatars \
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
        # The login screen (README "Login screen", nix/greeter.nix): the
        # greeter config of the same shell, run by greetd's arbor.
        makeWrapper ${quickshell}/bin/quickshell $out/bin/hearth-greeter \
          --add-flags "-p $out/share/hearth/shell/greeter.qml" \
          --prefix PATH : ${lib.makeBinPath runtimeDeps}:$out/share/hearth/helpers \
          --prefix QML_IMPORT_PATH : ${qmlPath} \
          --prefix QT_PLUGIN_PATH : ${pluginPath} \
          --set HEARTH_GREETER 1 \
          --set-default HEARTH_AVATAR_DIR $out/share/hearth/avatars \
          --set-default QT_QPA_PLATFORM wayland \
          --set-default HEARTH_FONT_DIR ${fontDir} \
          --set-default HEARTH_XKB_RULES ${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.lst
        # From a text console when the lock screen is stuck (README: Lock screen).
        ln -s $out/share/hearth/helpers/hearth-recover-lock $out/bin/hearth-recover-lock
        # GTK_MODULES=appmenu-gtk-module (arbor/config.kdl) finds it through
        # GTK_PATH's /run/current-system/sw/lib/gtk-3.0 with hearth installed.
        mkdir -p $out/lib/gtk-3.0/modules
        ln -s ${appmenu-gtk-module}/lib/gtk-3.0/modules/libappmenu-gtk-module.so $out/lib/gtk-3.0/modules/
        runHook postInstall
      '';
      meta.mainProgram = "hearth";
    };

    # Boot visuals ("Boot" in README.md): Plymouth splash and
    # GRUB menu themes, plus a VM test that screenshots both.
    boot = import ./boot { inherit pkgs; };
  in {
    packages.${system} = {
      default = hearth;
      inherit hearth quickshell appmenu-gtk-module;
      inherit (boot) plymouth-theme-hearth grub-theme-hearth grub-theme-hearth-5k;
      boot-screenshots = import ./boot/vm-test.nix { inherit pkgs boot; };
    };

    # The login screen (README "Login screen"): greetd + arbor + hearth-greeter.
    nixosModules.greeter = import ./nix/greeter.nix self;

    # `nix develop`, then `quickshell -p shell` runs straight from the
    # checkout and hot-reloads on every save.
    devShells.${system}.default = pkgs.mkShell {
      packages = runtimeDeps ++ [ pkgs.kdePackages.qtdeclarative ];
      shellHook = ''
        export PATH="$PWD/helpers:$PATH"
        export HEARTH_FONT_DIR=''${HEARTH_FONT_DIR:-${fontDir}}
        export QML_IMPORT_PATH=${qmlPath}''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}
        export QT_PLUGIN_PATH=${pluginPath}''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
        export HEARTH_BACKGROUND_DIRS=''${HEARTH_BACKGROUND_DIRS:-${backgroundDirs}}
      '';
    };
  };
}
