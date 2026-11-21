# Boots an EFI VM (OVMF -> GRUB -> Plymouth) with hearth's boot themes and
# saves screenshots of the GRUB menu, the boot splash and the password
# prompt to $out. `nix build .#boot-screenshots`.
# Nothing here touches the host's bootloader.
{ pkgs, boot }:
pkgs.testers.runNixOSTest {
  name = "hearth-boot-screenshots";
  nodes.machine = { pkgs, lib, ... }: {
    virtualisation = {
      useBootLoader = true;
      useEFIBoot = true;
      memorySize = 2048;
      # A 3840x1600 framebuffer, like the real gfxmode, so GRUB and Plymouth
      # get the same sizes as on the LG.
      qemu.options = [ "-vga none" "-device VGA,edid=on,xres=3840,yres=1600,vgamem_mb=128" ];
    };
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.timeout = lib.mkForce 60;
    boot.loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      theme = boot.grub-theme-hearth;
      splashImage = null;
      gfxmodeEfi = "3840x1600,auto";
      # Fake entries so the icon row shows what the real machine has.
      extraEntries = ''
        menuentry "Windows Boot Manager" --class windows --class os {
          echo "fake"
        }
        menuentry "UEFI Firmware Settings" --class efi {
          fwsetup
        }
      '';
    };
    boot.initrd.systemd.enable = true;
    boot.initrd.kernelModules = [ "bochs" ];
    boot.plymouth = {
      enable = true;
      theme = "hearth";
      themePackages = [ boot.plymouth-theme-hearth ];
      font = "${pkgs.inter}/share/fonts/truetype/InterVariable.ttf";
      extraConfig = ''
        ShowDelay=0
        DeviceScale=1
      '';
    };
    # The test VM has a serial console (the real machine has none); without
    # this plymouth falls back to text on every console.
    boot.kernelParams = [ "quiet" "splash" "video=3840x1600" "plymouth.ignore-serial-consoles" ];
    # Keep tty1 free for the password prompt test after boot.
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;
  };

  testScript = ''
    import time
    machine.start()
    # OVMF, then GRUB: give it time to draw the menu and count a few seconds.
    time.sleep(12)
    machine.screenshot("grub-menu")
    machine.send_key("down")
    time.sleep(1)
    machine.screenshot("grub-windows-selected")
    machine.send_key("up")
    time.sleep(1)
    machine.send_key("ret")
    for i in range(16):
        time.sleep(0.5)
        machine.screenshot(f"splash-{i:02d}")
    machine.wait_for_unit("multi-user.target")

    # Password prompt: start a fresh plymouthd on tty1 and ask.
    machine.succeed("chvt 1")
    print(machine.succeed("cat /proc/cmdline; ls -l /dev/dri; journalctl -b -o cat | grep -i plymouth | head -40"))
    machine.succeed("plymouthd --mode=boot --tty=tty1 --pid-file=/run/plymouth-test.pid --debug --debug-file=/tmp/plymouth-debug.log >/dev/null 2>&1")
    machine.succeed("plymouth show-splash")
    time.sleep(2)
    machine.screenshot("splash-running")
    machine.succeed("(plymouth ask-for-password --prompt='Please enter passphrase for disk cryptroot' > /tmp/pw &) ")
    time.sleep(2)
    machine.screenshot("password-empty")
    machine.send_chars("hunter2")
    time.sleep(1)
    machine.screenshot("password-typed")
    machine.send_key("ret")
    time.sleep(1)
    machine.screenshot("after-password")
    machine.succeed("plymouth quit")
    print(machine.succeed("grep -iv 'ply-terminal\\|keyboard' /tmp/plymouth-debug.log | head -150"))
  '';
}
