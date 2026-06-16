# Board module for the Banana Pi BPI-F3 (SpacemiT K1, RISC-V).
#
# Headless mainline target: a recent nixpkgs kernel with the in-tree
# k1-bananapi-f3 device tree and the SpacemiT K1 drivers forced on. No GPU/NPU
# (those are vendor-kernel only). Serial / SD / eMMC / ethernet are supported.
{ lib, pkgs, ... }:
{
  boot = {
    # Mainline kernel from nixpkgs (no custom-kernel machinery needed — the K1
    # SoC support and the BPI-F3 DTS are upstream).
    kernelPackages = pkgs.linuxPackages_latest;

    # nixpkgs' generated kernel config does not necessarily enable the SpacemiT
    # K1 platform/drivers, so force them on. Storage/clock/pinctrl/serial are
    # built in (=yes) so the board can reach its rootfs without relying on initrd
    # module ordering. Symbol names verified against the mainline riscv defconfig.
    kernelPatches = [
      {
        name = "spacemit-k1";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          ARCH_SPACEMIT = yes;
          SPACEMIT_K1_CCU = yes; # clock controller
          SPACEMIT_CCU = yes;
          PINCTRL_SPACEMIT_K1 = yes;
          GPIO_SPACEMIT_K1 = yes;

          # UART0 debug console
          SERIAL_8250 = yes;
          SERIAL_8250_CONSOLE = yes;
          SERIAL_8250_DW = yes;

          # SD / eMMC host controllers (builtin). The block layer (MMC_BLOCK) is
          # =m upstream; rather than rebuild the kernel to make it builtin, we
          # force-load mmc_block in the initrd (boot.initrd.kernelModules below).
          MMC_SDHCI = yes;
          MMC_SDHCI_PLTFM = yes;
          MMC_SDHCI_OF_K1 = yes;
          MMC_SDHCI_OF_DWCMSHC = yes;

          # Gigabit Ethernet
          NET_VENDOR_SPACEMIT = yes;
          SPACEMIT_K1_EMAC = module;
        };
      }
    ];

    initrd.availableKernelModules = lib.mkForce [
      "ext4"
      "sd_mod"
      "mmc_block"
      "xhci_hcd"
      "usbhid"
      "hid_generic"
    ];

    # MMC_BLOCK is =m upstream and udev didn't autoload it in the initrd (root on
    # the SD card then timed out). Force-load it early so /dev/mmcblk* appears.
    initrd.kernelModules = [ "mmc_block" ];

    # Let us into a root shell in the initrd if root isn't found, so failures are
    # debuggable (dmesg, ls /dev/mmc*) instead of a locked emergency console.
    initrd.systemd.emergencyAccess = true;

    supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];
  };

  hardware = {
    deviceTree.name = "spacemit/k1-bananapi-f3.dtb";
    enableRedistributableFirmware = true;

    # Mainline 7.0.x only wires up the K1 eMMC (mmc@d4281000); the BPI-F3's
    # removable SD-card slot controller (SDH0 @ d4280000) is absent from the DTS,
    # so the kernel can't see the SD card we boot from. Add it back, mirroring the
    # working eMMC node but with the SDH0 clocks/resets/IRQ and broken-cd (poll for
    # the card, since there's no card-detect line wired here). Same driver
    # (spacemit,k1-sdhci); U-Boot already powered/muxed the slot.
    deviceTree.overlays = [
      {
        name = "bpi-f3-sdhci0-sdcard";
        filter = "k1-bananapi-f3.dtb";
        dtsText = ''
          /dts-v1/;
          /plugin/;
          #include <dt-bindings/clock/spacemit,k1-syscon.h>

          // NixOS's apply_overlays.py only applies an overlay to a base DTB whose
          // root compatible intersects the overlay's root compatible, so declare
          // the board compatible here (matches k1-bananapi-f3.dts).
          / {
            compatible = "bananapi,bpi-f3", "spacemit,k1";
          };

          &{/soc/storage-bus} {
            mmc@d4280000 {
              compatible = "spacemit,k1-sdhci";
              reg = <0x0 0xd4280000 0x0 0x200>;
              clocks = <&syscon_apmu CLK_SDH_AXI>,
                       <&syscon_apmu CLK_SDH0>;
              clock-names = "core", "io";
              resets = <&syscon_apmu RESET_SDH_AXI>,
                       <&syscon_apmu RESET_SDH0>;
              reset-names = "axi", "sdh";
              interrupts = <99>;
              bus-width = <4>;
              broken-cd;
              // microSD slot has no write-protect tab; without this the
              // controller's WP sense reads "protected" and the card mounts
              // read-only (root then fails). Force it writable.
              disable-wp;
              // It's an SD-card slot: not eMMC, not SDIO. no-sdio also avoids the
              // driver's set_uhs_signaling VDD_180 write to HOST_CONTROL2 that
              // faulted (only taken when !NO_SDIO); no-mmc skips the eMMC HS400
              // ops; no-1-8-v keeps it on the 3.3V high-speed path for now.
              no-mmc;
              no-sdio;
              no-1-8-v;
              status = "okay";
            };
          };
        '';
      }
    ];
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

  # Headless: serial is the primary console; disable the hvc0 getty that some
  # RISC-V profiles enable.
  systemd.services."serial-getty@hvc0".enable = false;

  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PasswordAuthentication = lib.mkDefault true;
    };
    openFirewall = lib.mkDefault true;
  };

  environment.systemPackages = with pkgs; [
    htop
    minicom
    lm_sensors
    i2c-tools
    dnsutils
    ethtool
    kmod
    git
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
