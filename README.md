# nixos-bpi-f3

NixOS for the [Banana Pi BPI-F3](https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3) — an
octa-core [SpacemiT K1](https://www.spacemit.com/en/key1/) RISC-V SBC (RVA22 + RVV 1.0).

This flake **cross-compiles** a headless NixOS SD/eMMC image from an `x86_64` host to `riscv64`,
with the SpacemiT vendor bootloader (U-Boot 2022.10 + OpenSBI) built from source and embedded in
the image. There is no turnkey NixOS image for this board upstream — this is a "roll your own"
build, adapted from [nixos-licheepi4a](https://github.com/randomizedcoder/nixos-licheepi4a).

## Quick start

You build on an **`x86_64-linux`** machine; the flake cross-compiles to `riscv64` automatically
(it sets `nixpkgs.crossSystem`), so there is nothing special to configure — just `nix build`.

**Prerequisites**

- Nix with flakes enabled. Either use `--extra-experimental-features 'nix-command flakes'` on each
  command, or add to `~/.config/nix/nix.conf` (or `/etc/nix/nix.conf`):
  ```
  experimental-features = nix-command flakes
  ```
- A fast x86_64 builder with plenty of disk/RAM. Because we target `rv64gcv` (see Scope), the build
  gets **no** binary-cache hits and compiles the cross toolchain + the whole closure from source —
  budget a long first build (hours, not minutes) and tens of GB of store.

**Clone, build, flash**

```sh
# 1. Clone
git clone https://github.com/randomizedcoder/nixos-bpi-f3.git
cd nixos-bpi-f3

# 2. Cross-compile the SD image (runs on x86_64, produces a riscv64 image).
#    Tip: add `--log-format internal-json -v |& nom` (nix-output-monitor) to watch progress,
#    or `-j auto` to use all cores.
nix build .#sdImage

# 3. Flash the whole image to an SD card (bootloader blobs are already embedded — see below).
lsblk                                   # find your card, e.g. /dev/sdX  (NOT a partition)
sudo dd if=result/sd-image/nixos-bpi-f3-sd-image-*.img \
        of=/dev/sdX bs=4M conv=fsync status=progress

# 4. Insert the card, connect a USB-UART (115200 8N1), power on, and log in as bpi / bpi-f3.
```

That's it — no manual U-Boot flashing, no separate firmware step. The SpacemiT bootloader is built
from source and `dd`'d into the image during the build.

> First time on RISC-V Nix? You don't need a riscv64 machine or QEMU — cross-compilation does it all
> on x86_64. If a build step is too slow locally, point Nix at a beefier
> [remote builder](https://nix.dev/manual/nix/stable/advanced-topics/distributed-builds).

## Scope

- **Headless, mainline kernel.** Uses a recent nixpkgs kernel with the in-tree
  `k1-bananapi-f3` device tree. Serial, SD/eMMC, USB and Gigabit Ethernet are supported.
- **No GPU / NPU.** The IMG BXE GPU and the AI accelerator only work on the vendor (Bianbu) kernel.
  If you need them, you'll have to package that kernel — out of scope here.
- **ISA baseline `rv64gcv` (RVV 1.0 enabled).** The K1's X60 cores implement RVV 1.0. Note this
  diverges from the riscv64 community binary caches (which target `rv64gc`), so **the whole closure
  is built locally** — the first build is long and gets no cache hits. Build it on a fast machine.

## Repository layout

The `flake.nix` is intentionally thin; everything substantive is a module/derivation under `nix/`:

```
flake.nix                              # inputs + outputs wiring
nix/
  cross.nix                            # cross target: riscv64, rv64gcv / lp64d
  overlay.nix                          # exposes the bootloader packages
  modules/
    bpi-f3.nix                         # board module: kernel, K1 driver config, console, firmware
    user-group.nix                     # default user / hostname
    sd-image/
      sd-image.nix                     # patched generic sd-image module (MBR + raw-blob dd hook)
      sd-image-bpi-f3.nix              # board image: extlinux, kernelParams, dd of the boot blobs
  pkgs/
    u-boot/default.nix                 # vendor U-Boot -> FSBL.bin, bootinfo_emmc.bin, u-boot.itb
    opensbi/default.nix                # vendor OpenSBI -> fw_dynamic.itb
```

## Build outputs

The [Quick start](#quick-start) covers the common path (`nix build .#sdImage`). Individual outputs:

```sh
nix build .#sdImage    # default; the full SD image -> result/sd-image/*.img (uncompressed)
nix build .#uboot      # bootloader only: FSBL.bin, bootinfo_emmc.bin, u-boot.itb
nix build .#opensbi    # OpenSBI only: fw_dynamic.itb
```

Building `.#uboot` / `.#opensbi` on their own is handy when iterating on the (highest-risk) vendor
bootloader build without rebuilding the kernel and rootfs.

## Flashing

See [Quick start](#quick-start) step 3 for the `dd` command. Two things worth knowing:

- The bootloader blobs are embedded at their raw offsets during the build, so a plain whole-image
  `dd` is all that's needed — no separate U-Boot flashing.
- The root (ext4) partition **auto-expands** to fill the card on first boot.
- The same image boots from **eMMC** too (the BootROM checks both); write it to the eMMC device the
  same way.

## Boot flow & on-disk layout

The SpacemiT BootROM reads a small boot-info header at sector 0, then chains through the FSBL (SPL),
OpenSBI and U-Boot. These live at fixed raw sector offsets ahead of the first partition (matching
Armbian's `write_uboot_platform`):

| Artifact | Sector | Byte offset | Source |
| --- | --- | --- | --- |
| `bootinfo_emmc.bin` | 0 | `0x0` | `.#uboot` |
| `FSBL.bin` (SPL) | 1 | `0x200` | `.#uboot` |
| `fw_dynamic.itb` (OpenSBI) | 1280 | `0x140000` | `.#opensbi` |
| `u-boot.itb` (U-Boot proper) | 2048 | `0x200000` | `.#uboot` |

The two partitions (both in the one MBR table, first one starting at 16 MiB) are:

| Part | Filesystem | Label | Contents |
| --- | --- | --- | --- |
| 1 | FAT32 (`vfat`) | `BOOT` | `extlinux.conf` + kernel + DTB + initrd |
| 2 | ext4 | `NIXOS_SD` | root filesystem (auto-expands on first boot) |

### Why the partition table is MBR, not GPT

The on-disk **partition table is MBR** (a.k.a. "msdos"/"dos"). Note this is a *different layer* from
the boot partition's **FAT32 filesystem** — "msdos" as a partition *table* means MBR, while FAT32 is
the *filesystem* living inside partition 1. They're independent; FAT32 works inside either an MBR or a
GPT partition.

We must use MBR because of the raw-sector boot blobs above:

- A **GPT** keeps its primary header at **sector 1 (LBA1)** — exactly where `FSBL.bin` is `dd`'d.
  Writing the SPL there corrupts the GPT.
- **MBR** keeps all its metadata in **sector 0** only (partition table at byte offset 446). The tiny
  (~80 byte) `bootinfo_emmc.bin` at offset 0 fits *before* that table, and sectors 1+ are free for the
  bootloader. No collision.

This is exactly what Armbian — one of the distros listed on the
[BPI-F3 page](https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3) — does for this board. From
`config/sources/families/spacemit.conf`:

```bash
pre_prepare_partitions() {
	declare -g OFFSET="4"                       # first partition at 4 MiB (we use 16 MiB)
	declare -g IMAGE_PARTITION_TABLE="msdos"    # MBR, not GPT
}
```

which Armbian's core turns into an `sfdisk` `label: dos` (MBR) table.

### Boot chain

BootROM → FSBL (SPL) → OpenSBI → U-Boot proper → extlinux → Linux kernel.

## Serial console

Connect a 3.3 V USB-UART to the F3's debug UART header and open it at **115200 8N1**:

```sh
minicom -D /dev/ttyUSB0 -b 115200      # or: picocom -b 115200 /dev/ttyUSB0
```

Kernel console is `ttyS0,115200` with `earlycon=sbi` for early output.

## Default login

- user: **`bpi`**
- password: **`bpi-f3`**

Change these in `nix/modules/user-group.nix` (regenerate the hash with `mkpasswd -m yescrypt`)
before putting the board on an untrusted network.

## Known limitations / status

- **GPU/NPU:** not supported (vendor kernel only).
- **PCIe:** the mainline SpacemiT PCIe host/PHY support is recent; verify on your kernel version.
- **Wi-Fi:** the on-board chip (e.g. `8852bs`) needs an out-of-tree driver — not included.
- **Binary caches:** `rv64gcv` means no community-cache hits; expect long first builds.

## References

- BPI-F3 docs: <https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3>
- SpacemiT U-Boot 2022.10: <https://gitee.com/spacemit-buildroot/uboot-2022.10>
- SpacemiT OpenSBI: <https://gitee.com/spacemit-buildroot/opensbi>
- Armbian (BPI-F3 board + spacemit family configs): <https://github.com/BPI-SINOVOIP/armbian-build>
- Base flake (Lichee Pi 4A): <https://github.com/randomizedcoder/nixos-licheepi4a>

See [`IMPLEMENTATION.md`](./IMPLEMENTATION.md) for the design and [`PROGRESS.md`](./PROGRESS.md) for status.
