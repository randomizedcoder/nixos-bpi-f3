# Progress

Running log for the [implementation plan](./IMPLEMENTATION.md). Updated as work proceeds.

## Status

| # | Step | Status | Notes |
| --- | --- | --- | --- |
| 0 | In-repo docs (`IMPLEMENTATION.md`, `PROGRESS.md`) | ✅ done | Plan committed in-repo. |
| 1 | Thin `flake.nix` | ✅ done | nixpkgs + 2 gitee vendor inputs; outputs sdImage/uboot/opensbi. |
| 2 | `nix/cross.nix` (rv64gcv/lp64d) | ✅ done | |
| 3 | `nix/pkgs/opensbi/default.nix` | ✅ done | `PLATFORM=generic PLATFORM_DEFCONFIG=k1_defconfig` → fw_dynamic.itb. |
| 4 | `nix/pkgs/u-boot/default.nix` | ✅ done | buildUBoot, k1_defconfig + BPI-F3 extraConfig → FSBL.bin/bootinfo_emmc.bin/u-boot.itb. |
| 5 | `nix/overlay.nix` | ✅ done | Injects vendor srcs from flake inputs. |
| 6 | `nix/modules/sd-image/sd-image.nix` | ✅ done | Ported from LP4A; switched GPT→**MBR** (FSBL@sector1 vs GPT header). |
| 7 | `nix/modules/sd-image/sd-image-bpi-f3.nix` | ✅ done | extlinux + dd blobs at sectors 0/1/1280/2048; 16 MiB gap. |
| 8 | `nix/modules/bpi-f3.nix` (board module) | ✅ done | linuxPackages_latest + forced K1 Kconfig; deviceTree k1-bananapi-f3.dtb. |
| 9 | `nix/modules/user-group.nix` | ✅ done | user `bpi` / pass `bpi-f3` (real yescrypt hash). |
| 10 | Rewrite `README.md` | ✅ done | Build/flash/serial guide + boot-blob offset table. |
| V | Verify: evaluation | ✅ done | `nix eval` of `.#opensbi`, `.#uboot`, `.#sdImage` drvPaths all succeed. |
| V2 | Verify: full build (compile) | ✅ done | `nix build .#sdImage` succeeds end-to-end (after the 2 fixes below). 3.15 GiB image. |
| V2a | Verify: on-disk layout | ✅ done | MBR table; part1 FAT32 bootable @16 MiB; part2 ext4. All 4 blobs byte-exact at sectors 0/1/1280/2048; bootinfo magic 0xB00714F0 @0. extlinux.conf + kernel + initrd + k1-bananapi-f3.dtb present. |
| V3 | Verify: hardware bring-up | ⬜ todo | Flash, attach UART, watch OpenSBI→U-Boot→extlinux→kernel; confirm SD/eMMC/eth. (User, on-device.) |

Legend: ⬜ todo · 🟡 in progress · ✅ done · ⛔ blocked

## Log

- **2026-06-14** — Step 0 complete. Plan written to `IMPLEMENTATION.md`; this progress doc created.
- **2026-06-14** — Steps 1–10 implemented. Key decisions during build:
  - Vendor sources pinned via `git+https` flake inputs (gitee), tag `k1-bl-v2.2.10-release`
    (uboot `46a4f51…`, opensbi `34143f5…`). Both resolve fine over the network.
  - **Partition table is MBR, not GPT.** Armbian's SpacemiT family uses `msdos`; GPT's primary
    header at LBA1 would be clobbered by `FSBL.bin` (dd'd to sector 1). `bootinfo_emmc.bin` (~80 B)
    coexists with the MBR table at byte offset 446.
  - Bootloader blobs dd'd in `postBuildCommands` at sectors 0/1/1280/2048 (mirrors armbian's
    `write_uboot_platform`). 16 MiB firmware-partition gap clears them.
  - Kernel: `linuxPackages_latest` (nixpkgs unstable = 7.0.12) with K1 Kconfig forced on
    (`ARCH_SPACEMIT`, `SPACEMIT_K1_CCU`, `PINCTRL/GPIO_SPACEMIT_K1`, `MMC_SDHCI_OF_K1`,
    `SERIAL_8250_DW`, `SPACEMIT_K1_EMAC`). Symbols verified against mainline riscv defconfig.
- **2026-06-14** — Verification: fixed `extraStructuredConfig`→`structuredExtraConfig` (nixpkgs
  rename) in the kernelPatches entry, caught by evaluation. All flake inputs resolve and
  `.#opensbi`, `.#uboot`, `.#sdImage` evaluate to derivations successfully.
- **Next:** run the full `nix build .#sdImage` on the fast host (expect a long first build — no
  cache hits at `rv64gcv`), then flash and bring up on hardware. Watch the vendor U-Boot build
  (python signing/bootinfo tooling) — the documented fallback is prebuilt blobs if it fights.
- **2026-06-14** — First `nix build .#sdImage` (`--keep-going`) run. Cross toolchain (GCC 15.2.0 for
  rv64gcv) + binutils/glibc built fine. **OpenSBI build failed**: vendor tree has
  `typedef int bool;` in `sbi_types.h`; GCC 15 defaults to `-std=c23` (where `bool` is a keyword),
  fatal under `-Werror`. **Fix applied:** added `platform-cflags-y=-std=gnu17` to the opensbi
  makeFlags (folded into global CFLAGS, so it covers lib/sbi). Same pattern as the LP4A opensbi.
  Letting the `--keep-going` run continue to also exercise the U-Boot + kernel builds before
  re-running with the fix.
- **2026-06-14/15** — ✅ **Vendor U-Boot built cleanly from source** — the highest-risk derivation.
  The SPL compiled, the Python tooling (`build_binary_file.py`) ran without error and emitted FSBL +
  all bootinfo images, and the FIT (`u-boot.itb`) assembled. Output verified:
  - `bootinfo_emmc.bin` = **80 bytes** (confirms it fits before the MBR table at byte 446 — the
    empirical basis for the GPT→MBR decision),
  - `FSBL.bin` = 210,592 B (sector 1 → ~412, clear of OpenSBI @1280),
  - `u-boot.itb` = 2,043,686 B (sector 2048 → ~6040, well within the 16 MiB gap).
  No overlaps; the offset layout is validated. The from-source bootloader approach works — the
  prebuilt-blob fallback is not needed.
- **2026-06-15** — Second failure surfaced near the end of the first run: **`efl` failed to
  cross-compile** (`eolian_gen` build tool not found for riscv64), cascading up through
  `fastfetch` → `system-path` → the image. `fastfetch` (cosmetic, headless-irrelevant) was pulling
  the entire `efl` GUI toolkit. **Fix:** removed `fastfetch` from `environment.systemPackages`.
  The kernel (`linux-7.0.3`/`7.0.12`) + initrd had already built fine with the forced K1 config.
- **2026-06-15** — ✅ **Full build succeeds.** Re-ran `nix build .#sdImage` with both fixes (OpenSBI
  `-std=gnu17`, fastfetch removed); everything else cached. Produced a 3.15 GiB image. Verified:
  - partition table = MBR (`dos`), id 0x2178694e; part1 FAT32 bootable @ sector 32768 (16 MiB),
    part2 ext4;
  - all four bootloader blobs `cmp`-identical to the package outputs at sectors 0/1/1280/2048;
    bootinfo magic `0xB00714F0` at offset 0;
  - FAT boot partition holds `extlinux.conf` (correct serial-console cmdline), the kernel Image,
    initrd, and `spacemit/k1-bananapi-f3.dtb` (referenced via `FDT`).
  Software build + image layout fully validated. Only on-hardware boot (V3) remains.
