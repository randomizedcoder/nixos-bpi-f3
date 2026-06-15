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

          # SD / eMMC
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

    supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];
  };

  hardware = {
    deviceTree.name = "spacemit/k1-bananapi-f3.dtb";
    enableRedistributableFirmware = true;
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
