# SpacemiT vendor U-Boot 2022.10 for the K1 (Banana Pi BPI-F3).
#
# The K1 BootROM boot chain expects several structured blobs at fixed sector
# offsets on the boot medium (see modules/sd-image/sd-image-bpi-f3.nix). This
# derivation produces the three that come out of the U-Boot tree:
#
#   FSBL.bin          -> sector 1     (the SPL, wrapped + RSA2048-signed by tools/build_binary_file.py)
#   bootinfo_emmc.bin -> sector 0     (BootROM boot-info header; emitted alongside FSBL.bin)
#   u-boot.itb        -> sector 2048  (U-Boot proper, FIT of u-boot-nodtb.bin + board DTBs)
#
# OpenSBI's fw_dynamic.itb (sector 1280) is built separately (../opensbi); the
# U-Boot FIT does not embed it.
#
# Build recipe mirrors Armbian's spacemit family + bananapif3 board tweaks
# (armbian-build: config/sources/families/spacemit.conf, config/boards/bananapif3.conf):
#   make k1_defconfig && make            # default `all` builds the SPL/FSBL + bootinfo
#   make u-boot.itb                      # FIT assembled from u-boot-nodtb.bin via mkimage
#
# `src` is injected by the overlay from the `uboot-spacemit` flake input
# (gitee.com/spacemit-buildroot/uboot-2022.10, tag k1-bl-v2.2.10-release).
{
  lib,
  buildUBoot,
  src,
}:

buildUBoot {
  version = "2022.10-k1-bl-v2.2.10";
  inherit src;

  defconfig = "k1_defconfig";

  # Extra Kconfig from armbian's post_config_uboot_target__extra_configs_for_bananapi_f3.
  # Appended to .config; `make` runs syncconfig to fold them in.
  extraConfig = ''
    CONFIG_SD_BOOT=y
    CONFIG_EXT4_WRITE=y
    CONFIG_FS_BTRFS=y
    CONFIG_CMD_BTRFS=y
    CONFIG_SPI_FLASH_USE_4K_SECTORS=y
  '';

  # Build the default target (SPL -> FSBL.bin + bootinfo_*.bin, plus u-boot proper),
  # then the U-Boot FIT explicitly (it is a standalone Makefile target, not in ALL-y).
  buildFlags = [
    "all"
    "u-boot.itb"
  ];

  extraMeta.platforms = [ "riscv64-linux" ];

  filesToInstall = [
    "FSBL.bin"
    "bootinfo_emmc.bin"
    "u-boot.itb"
  ];
}
