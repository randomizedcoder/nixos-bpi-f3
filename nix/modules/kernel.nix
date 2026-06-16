# Kernel + initrd for the Banana Pi BPI-F3 (SpacemiT K1).
#
# Mainline kernel from nixpkgs (no custom-kernel machinery — the K1 SoC support
# and the BPI-F3 DTS are upstream), with the SpacemiT K1 drivers forced on since
# nixpkgs' generated config does not necessarily enable them.
{ lib, pkgs, ... }:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_latest;

    # Storage/clock/pinctrl/serial built in (=yes) so the board reaches its rootfs
    # without relying on initrd module ordering. Symbol names verified against the
    # mainline riscv defconfig.
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
          # force-load mmc_block in the initrd (initrd.kernelModules below).
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

    initrd = {
      availableKernelModules = lib.mkForce [
        "ext4"
        "sd_mod"
        "mmc_block"
        "xhci_hcd"
        "usbhid"
        "hid_generic"
      ];

      # MMC_BLOCK is =m upstream and udev didn't autoload it in the initrd (root
      # on the SD card then timed out). Force-load it early so /dev/mmcblk* appears.
      kernelModules = [ "mmc_block" ];

      # Let us into a root shell in the initrd if root isn't found, so failures are
      # debuggable (dmesg, ls /dev/mmc*) instead of a locked emergency console.
      systemd.emergencyAccess = true;
    };

    supportedFilesystems = lib.mkForce [
      "vfat"
      "ext4"
      "btrfs"
    ];
  };
}
