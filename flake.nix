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
    quickshell = pkgs.quickshell.overrideAttrs (old: {
      version = "0.3.2";
      src = quickshell-src;
      # The shell never goes through Qt's Wayland reconnect (Quickshell's own
      # protocol objects don't survive it: it crashed in handleScreenRemoved);
      # apps it launches still get QT_WAYLAND_RECONNECT. See bin/hearth below.
      # Screencopy (screenshot editor, previews) bound a second wl_output with
      # Qt's own wrapper class; a wl_surface.enter for it crashed Qt
      # (QWaylandSurface::oldestEnteredScreen).
      patches = (old.patches or [ ]) ++ [
        ./nix/quickshell-child-reconnect.patch
        ./nix/quickshell-screencopy-output.patch
      ];
    });

    # Spotlight's indexer (nix/recoll.nix): recoll without its GUI.
    recoll = pkgs.callPackage ./nix/recoll.nix { };
    # llama.cpp for the AI hub's managed server (helpers/hearth-llama-server):
    # the Vulkan build, which is in the binary cache and runs well on RDNA 3.
    llama-cpp = pkgs.llama-cpp-vulkan;

    python = pkgs.python3.withPackages (p: [
      p.dbus-python p.pygobject3
      p.websockets                       # hearth-voice: the WhisperLive server
      (p.toPythonModule recoll)          # hearth-search: recoll's Python API
    ]);

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
      # Spotlight (helpers/hearth-search, hearth-indexer): the index, the
      # calculator and unit conversions, PDF previews.
      recoll libqalculate poppler-utils
      # Voice assistant (helpers/hearth-voice): spoken replies, the
      # listening sounds
      # come from sound-theme-freedesktop (HEARTH_SOUND_DIR below).
      piper-tts
      llama-cpp
      # About This Computer (helpers/hearth-sysinfo).
      usbutils vulkan-tools
      # Bluetooth settings (bar/indicators/Bluetooth.qml), in tessera.
      bluetuith
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

    # Shown in About This Computer: the commit this build came from.
    hearthVersion = "0.1.0 (${self.shortRev or self.dirtyShortRev or "dev"})";

    hearth = pkgs.stdenvNoCC.mkDerivation {
      pname = "hearth";
      version = "0.1.0";
      src = lib.cleanSource ./.;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/hearth $out/bin
        # arbor/: the arbor config devloop installs live into
        # ~/.config/hearth/arbor/ with each new hearth (no nixos-rebuild).
        cp -r shell helpers hypr vicinae swaync arbor $out/share/hearth/
        # Built-in user pictures (avatars/CREDITS.md), for Settings > Users &
        # Accounts and the login screen: $out/share/hearth/avatars.
        cp -r avatars $out/share/hearth/
        # hearth Settings and About This Computer as apps (Dock, Spotlight,
        # Vicinae), replacing KDE's System Settings and Info Center.
        mkdir -p $out/share/applications
        cp applications/*.desktop $out/share/applications/
        chmod +x $out/share/hearth/helpers/*
        patchShebangs $out/share/hearth/helpers
        # Apps launched from the dock inherit the bar's working directory;
        # start in $HOME so a bar run from a since-deleted directory doesn't
        # hand every app a dangling cwd.
        mkdir -p $out/libexec
        makeWrapper ${quickshell}/bin/quickshell $out/libexec/hearth-shell \
          --run 'cd "$HOME"' \
          --run 'if [ -n "''${QT_WAYLAND_RECONNECT+x}" ]; then export QS_CHILD_QT_WAYLAND_RECONNECT="$QT_WAYLAND_RECONNECT"; unset QT_WAYLAND_RECONNECT; fi' \
          --add-flags "-p $out/share/hearth/shell" \
          --prefix PATH : ${lib.makeBinPath runtimeDeps}:$out/share/hearth/helpers \
          --prefix QML_IMPORT_PATH : ${qmlPath} \
          --prefix QT_PLUGIN_PATH : ${pluginPath} \
          --set-default HEARTH_BACKGROUND_DIRS ${backgroundDirs} \
          --set-default HEARTH_AVATAR_DIR $out/share/hearth/avatars \
          --set-default HEARTH_FONT_DIR ${fontDir} \
          --set-default HEARTH_VERSION "${hearthVersion}" \
          --set-default HEARTH_SOUND_DIR ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo \
          --set-default HEARTH_XKB_RULES ${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.lst
        # hearth runs the shell and starts it again when arbor restarts in
        # place (`arbor msg action reload-binary`, or after a crash): the shell
        # quits with 75 when arbor's event stream drops (ArborBackend.qml), or
        # Qt ends it with 255 when the Wayland connection breaks (it never
        # reconnects: the patch above). At most 5 restarts a minute.
        cat > $out/bin/hearth <<EOF
        #!${pkgs.bash}/bin/bash
        export HEARTH_RESTARTER=1
        child=
        recent=()
        trap '[ -n "\$child" ] && kill -TERM "\$child" 2>/dev/null; wait "\$child"; exit 143' TERM INT HUP
        while :; do
          $out/libexec/hearth-shell "\$@" &
          child=\$!
          wait "\$child"; rc=\$?
          case \$rc in 75|255) ;; *) exit "\$rc" ;; esac
          now=\$(date +%s); keep=()
          for t in "\''${recent[@]}"; do (( now - t < 60 )) && keep+=("\$t"); done
          recent=("\''${keep[@]}" "\$now")
          (( \''${#recent[@]} > 5 )) && { echo "hearth: the shell keeps ending; giving up" >&2; exit "\$rc"; }
          echo "hearth: arbor restarted (exit \$rc); starting the shell again" >&2
          sleep 0.3
        done
        EOF
        chmod +x $out/bin/hearth
        # Talk to the running hearth whichever build started it: quickshell
        # matches instances by config path, so after a rebuild (or a bar
        # started from another build) `-p` finds nothing and every keybind
        # through hearth-ipc silently fails. Pick the newest hearth by pid.
        cat > $out/bin/hearth-ipc <<EOF
        #!${pkgs.runtimeShell}
        # The newest running instance of an installed hearth, as Quickshell
        # lists them: only real shell instances (not Quickshell's own helper
        # process, which has the same command line and is always newer) and
        # only this login's runtime dir (not smoke tests or nested test
        # sessions, which run with their own).
        pid=\$(${quickshell}/bin/quickshell list --all --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '[.[] | select(.config_path | test("^/nix/store/[^/]*-hearth-[^/]*/share/hearth/shell/shell.qml\$"))] | sort_by(.launch_time) | last | .pid // empty')
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
        # Spotlight's indexer and the AI hub's llama.cpp server, for the
        # systemd user units in nixosModules.ai.
        for t in hearth-indexer hearth-llama-server; do
          makeWrapper $out/share/hearth/helpers/$t $out/bin/$t \
            --prefix PATH : ${lib.makeBinPath runtimeDeps}:$out/share/hearth/helpers
        done
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
      inherit hearth quickshell appmenu-gtk-module recoll;
      inherit (boot) plymouth-theme-hearth grub-theme-hearth;
      boot-screenshots = import ./boot/vm-test.nix { inherit pkgs; module = self.nixosModules.boot; };
    };

    # The login screen (README "Login screen"): greetd + arbor + hearth-greeter.
    nixosModules.greeter = import ./nix/greeter.nix self;
    # Spotlight's indexer and the AI hub's llama.cpp server as user units
    # (README "Spotlight", "AI").
    nixosModules.ai = import ./nix/ai.nix self;
    # The boot menu and splash (README "Boot").
    nixosModules.boot = import ./nix/boot.nix self;

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
