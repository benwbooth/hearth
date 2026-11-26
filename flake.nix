{
  description = "hearth: a Quickshell desktop shell for Hyprland";

  # /etc/nixos sets `inputs.nixpkgs.follows`, so Quickshell links the same Qt
  # as the system's Qt plugins (the xdgdesktopportal platform theme, image
  # formats); a second Qt would fail to load them.
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
      p.cryptography                     # hearth-keyring-prompter: the keyring's secret exchange (AES)
      p.pyyaml                           # hearth-appmenu: menu modules (menus/*.yaml)
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
      wlogout hyprpaper grim satty
      wf-recorder vips
      pipewire wireplumber
      systemd procps coreutils gnugrep gawk util-linux iproute2
      swayidle
      python
      xprop   # hearth-appmenu: X11 windows' menu properties (xwayland-satellite)
      xrestop # hearth-appmenu: an X11 window's pid when it sets no _NET_WM_PID (XRes)
      tesseract # hearth_ocr_menu: popups no accessibility tree shows (Qt Quick menus), read off the screen
      # Portal backend (helpers/hearth-portal): org.gnome.* settings from
      # dconf, `gio launch` for the mail app.
      dconf glib
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
      # Cloud drives (helpers/hearth-rclone, Settings > Accounts).
      rclone
    ];

    # QtMultimedia for video wallpapers. (Kirigami and the org.kde.desktop
    # Controls style left with Plasma's `kde` platform theme, 2026-11-23.)
    qmlPath = lib.makeSearchPath "lib/qt-6/qml" [ pkgs.kdePackages.qtmultimedia ];
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
    appmenu-gtk2-module = pkgs.callPackage ./nix/appmenu-gtk-module.nix { gtk = pkgs.gtk2; gtkVersion = "2"; };
    # Global menus for Java Swing apps (README "Global menu"): the AT-SPI
    # bridge JAVA_TOOL_OPTIONS (arbor/config.kdl) loads into every JVM.
    java-atk-wrapper = pkgs.callPackage ./nix/java-atk-wrapper.nix { };

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
        cp -r shell helpers hypr vicinae arbor menus $out/share/hearth/
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
          --set-default HEARTH_XKB_RULES ${pkgs.xkeyboard_config}/share/X11/xkb/rules/evdev.lst \
          --set-default HEARTH_ATSPI_TYPELIB ${pkgs.at-spi2-core}/lib/girepository-1.0:${pkgs.gobject-introspection}/lib/girepository-1.0
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
        # Asked to stop: TERM the shell, KILL it if it hasn't gone in 4 s.
        # devloop KILLs this wrapper after 5 s, which would orphan a
        # lingering shell; one still holding the session lock then refused
        # the next hearth's lock (2026-11-21).
        # Each shell runs in its own process group (setsid), and when it ends
        # however it ends, so does the group: its long-lived helpers
        # (udisksctl/nmcli monitor, hearth-badges, hearth-accounts, ...) never
        # notice a dead parent and piled up by the hundred (2026-11-23). Apps
        # aren't in the group: the dock starts them with systemd-run and
        # execDetached gives each its own session.
        reap() {
          [ -n "\$child" ] || return 0
          kill -TERM -- "-\$child" 2>/dev/null || return 0
          for _ in \$(seq 20); do kill -0 -- "-\$child" 2>/dev/null || return 0; sleep 0.1; done
          kill -KILL -- "-\$child" 2>/dev/null
        }
        stop() {
          if [ -n "\$child" ]; then
            # The whole group at once: devloop KILLs this wrapper after 5 s.
            kill -TERM -- "-\$child" 2>/dev/null
            for _ in \$(seq 40); do kill -0 -- "-\$child" 2>/dev/null || break; sleep 0.1; done
            kill -KILL -- "-\$child" 2>/dev/null
            wait "\$child"
          fi
          exit 143
        }
        trap stop TERM INT HUP
        while :; do
          ${pkgs.util-linux}/bin/setsid $out/libexec/hearth-shell "\$@" &
          child=\$!
          wait "\$child"; rc=\$?
          reap
          case \$rc in 75|255) ;; *) exit "\$rc" ;; esac
          now=\$(date +%s); keep=()
          for t in "\''${recent[@]}"; do (( now - t < 60 )) && keep+=("\$t"); done
          recent=("\''${keep[@]}" "\$now")
          (( \''${#recent[@]} > 5 )) && { echo "hearth: the shell keeps ending; giving up" >&2; exit "\$rc"; }
          if [ "\$rc" = 75 ]; then echo "hearth: the shell asked to be restarted (exit 75); starting it again" >&2
          else echo "hearth: arbor restarted (exit \$rc); starting the shell again" >&2; fi
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
        # sessions, which run with their own). A test shell that shares the
        # runtime dir anyway (HEARTH_SESSION_DRYRUN=1, or another Wayland
        # display) is skipped: it took Super+L and every shortcut once.
        # When no shell is on our WAYLAND_DISPLAY, the newest non-test one is
        # used: apps started as user services get the user manager's
        # WAYLAND_DISPLAY, which a test session had once left pointing at its
        # own display (the Settings app then never opened).
        pid="" any=""
        for p in \$(${quickshell}/bin/quickshell list --all --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '[.[] | select(.config_path | test("^/nix/store/[^/]*-hearth-[^/]*/share/hearth/shell/shell.qml\$"))] | sort_by(.launch_time) | reverse | .[].pid'); do
          env=\$(tr '\\0' '\\n' < /proc/\$p/environ 2>/dev/null) || continue
          case "\$env" in *HEARTH_SESSION_DRYRUN=1*) continue ;; esac
          [ -z "\$any" ] && any=\$p
          if [ -n "\$WAYLAND_DISPLAY" ] && ! printf '%s\\n' "\$env" | grep -qx "WAYLAND_DISPLAY=\$WAYLAND_DISPLAY"; then continue; fi
          pid=\$p; break
        done
        [ -z "\$pid" ] && pid=\$any
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
        # systemd user units in nixosModules.ai; hearth-askpass, the system's
        # SUDO_ASKPASS / SSH_ASKPASS (hearth's password dialog).
        # hearth-appmenu: arbor starts its registrar first in a session (--registrar-only).
        for t in hearth-indexer hearth-llama-server hearth-accounts hearth-portal hearth-askpass hearth-appmenu; do
          makeWrapper $out/share/hearth/helpers/$t $out/bin/$t \
            --prefix PATH : ${lib.makeBinPath runtimeDeps}:$out/share/hearth/helpers
        done
        # Accounts (Settings > Accounts): the service apps ask for passwords
        # and sign-in tokens, started on demand by the session bus.
        mkdir -p $out/share/dbus-1/services
        cat > $out/share/dbus-1/services/io.github.benwbooth.Accounts.service <<EOF
        [D-BUS Service]
        Name=io.github.benwbooth.Accounts
        Exec=$out/bin/hearth-accounts serve
        EOF
        # hearth's desktop portal backend (helpers/hearth-portal): colour
        # scheme, notifications, permissions, Open With, print, web apps,
        # email. xdg-desktop-portal starts it on demand; route interfaces to
        # it with xdg.portal.config.<desktop> = { default = [ "hearth" ]; }
        # and add hearth to xdg.portal.extraPortals.
        cat > $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hearth.service <<EOF
        [D-BUS Service]
        Name=org.freedesktop.impl.portal.desktop.hearth
        Exec=$out/bin/hearth-portal serve
        EOF
        mkdir -p $out/share/xdg-desktop-portal/portals
        cat > $out/share/xdg-desktop-portal/portals/hearth.portal <<EOF
        [portal]
        DBusName=org.freedesktop.impl.portal.desktop.hearth
        Interfaces=org.freedesktop.impl.portal.Settings;org.freedesktop.impl.portal.Notification;org.freedesktop.impl.portal.Lockdown;org.freedesktop.impl.portal.Account;org.freedesktop.impl.portal.Access;org.freedesktop.impl.portal.AppChooser;org.freedesktop.impl.portal.DynamicLauncher;org.freedesktop.impl.portal.Email;org.freedesktop.impl.portal.Print;
        EOF
        # From a text console when the lock screen is stuck (README: Lock screen).
        ln -s $out/share/hearth/helpers/hearth-recover-lock $out/bin/hearth-recover-lock
        # GTK_MODULES=appmenu-gtk-module (arbor/config.kdl) finds it through
        # GTK_PATH's /run/current-system/sw/lib/gtk-3.0 with hearth installed.
        mkdir -p $out/lib/gtk-3.0/modules
        ln -s ${appmenu-gtk-module}/lib/gtk-3.0/modules/libappmenu-gtk-module.so $out/lib/gtk-3.0/modules/
        # The same for GTK 2 apps (same module name, GTK 2's own folder).
        mkdir -p $out/lib/gtk-2.0/modules
        ln -s ${appmenu-gtk2-module}/lib/gtk-2.0/modules/libappmenu-gtk-module.so $out/lib/gtk-2.0/modules/
        # GTK 2 has no built-in accessibility: GTK_MODULES' gail (in each
        # app's own GTK 2) and atk-bridge (here) put its windows on AT-SPI.
        ln -s ${pkgs.at-spi2-core}/lib/gtk-2.0/modules/libatk-bridge.so $out/lib/gtk-2.0/modules/
        # JAVA_TOOL_OPTIONS (arbor/config.kdl) loads the Java accessibility
        # bridge from /run/current-system/sw/lib/java-atk-wrapper.
        ln -s ${java-atk-wrapper}/lib/java-atk-wrapper $out/lib/java-atk-wrapper
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
      inherit hearth quickshell appmenu-gtk-module appmenu-gtk2-module java-atk-wrapper recoll;
      inherit (boot) plymouth-theme-hearth grub-theme-hearth;
      boot-screenshots = import ./boot/vm-test.nix { inherit pkgs; module = self.nixosModules.boot; };
    };

    # The login screen (README "Login screen"): greetd + arbor + hearth-greeter.
    nixosModules.greeter = import ./nix/greeter.nix self;
    # The global menu's system side (README "Global menu"): the
    # accessibility bus, the Flatpak guard for the Java bridge.
    nixosModules.global-menu = import ./nix/global-menu.nix self;
    # For app wrappers: Electron builds the accessibility tree hearth's
    # global menu reads (menus it doesn't export) only with these flags.
    lib.globalMenu.electronFlags = [ "--force-renderer-accessibility=basic" ];
    # Spotlight's indexer and the AI hub's llama.cpp server as user units
    # (README "Spotlight", "AI").
    nixosModules.ai = import ./nix/ai.nix self;
    # Apps start once hearth's tray, notifications and global menu are up.
    nixosModules.session = import ./nix/session.nix self;
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
