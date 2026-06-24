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
      {
        # Make `reboot`/`poweroff` actually reset the board. The vendor OpenSBI
        # has no SBI System-Reset (SRST) extension, so Linux's only working
        # reset path is the P1 PMIC driver (POWER_RESET_SPACEMIT_P1, builtin) —
        # but the MFD core doesn't register its cell, so it never binds. This
        # adds the cell. See the patch header for the full rationale.
        name = "spacemit-p1-reboot-cell";
        patch = ./spacemit-p1-reboot-cell.patch;
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
        # Root-on-NVMe (see nix/modules/nvme). The K1 PCIe controller is built
        # into the kernel (CONFIG_PCIE_SPACEMIT_K1=y / PHY_SPACEMIT_K1_PCIE=y),
        # so the bus is enumerated during kernel init and udev autoloads the
        # NVMe driver in stage-1. Only BLK_DEV_NVME is modular (=m upstream),
        # so it must be made available to the initrd here; nvme_core and the
        # rest of the closure are pulled in automatically.
        "nvme"
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
