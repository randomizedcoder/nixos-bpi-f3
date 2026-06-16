# Progress

Running log for the [implementation plan](./IMPLEMENTATION.md). Updated as work proceeds.

## Outcome

✅ **Done — boots to `bpi-f3 login:` on real hardware from the SD card** (NixOS 26.11, mainline kernel
7.0.12, `rv64gcv`). Verified working: serial console, SD root **r/w**, both Gigabit Ethernet ports
(`k1_emac`/RTL8211F, DHCP), NVMe over PCIe, USB 2.0/3.0, SSH.

Final working configuration:

- **U-Boot:** Armbian's fork (`pyavitz/spacemit-u-boot` @ `k1-bl-v2.2.9`) + its patch set — `001` adds
  the raw-offset SPL fallback (OpenSBI→`0x500`/sector 1280, U-Boot→`0x800`/sector 2048), `002`/`004` add
  the MMC boot target + extlinux. Banner renamed to "NixOS" via `CONFIG_LOCALVERSION`.
- **OpenSBI:** SpacemiT gitee tree, built with `platform-cflags-y=-std=gnu17` (GCC 15 / C23).
- **Image:** MBR table, four boot blobs `dd`'d at sectors 0/1/1280/2048, first partition at 16 MiB;
  extlinux boot; kernel cmdline kept under U-Boot's 256-byte cap.
- **Kernel:** nixpkgs `linuxPackages_latest` (7.0.12) with forced K1 Kconfig, `mmc_block` force-loaded in
  initrd, and a **DT overlay re-adding the SD-card slot** (`mmc@d4280000`,
  `no-mmc`/`no-sdio`/`no-1-8-v`/`broken-cd`/`disable-wp`) — mainline ships only the eMMC node.

Known minor: the RTC isn't persisted, so the clock relies on NTP at boot (TLS fails until
`systemd-timesyncd` syncs). See the README's *Challenges worked around* / *Limitations*.

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
| V3 | Verify: hardware bring-up | ✅ **done** | Boots to `bpi-f3 login:` on real hardware from SD. Root mounts r/w; both GbE NICs, NVMe/PCIe, USB2/3, SSH all up. |

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
- **2026-06-15** — First hardware boot attempt: card verified good on the device
  (`xxd /dev/sdb` shows bootinfo magic `f014 07b0`; MBR table; correct partitions), DIP switches at
  default (SD tried first), minicom 115200 8N1 flow-control off — but only a **brief garbled UART
  burst then silence**. Root-caused from the U-Boot source:
  - `common/spl/spl_mmc.c` (vanilla vendor U-Boot, which we built) loads OpenSBI/U-Boot **only from
    GPT partitions named "opensbi"/"uboot"** — it does NOT read raw sector offsets. Our MBR + raw
    offsets meant the SPL/FSBL ran, found neither partition, and hung → exactly the symptom.
  - Armbian's raw-offset scheme works only because of its `001-MBR-support.patch`, which hardcodes the
    fallback `opensbi -> 0x500 (sector 1280)`, `uboot -> 0x800 (sector 2048)` — **the exact offsets we
    already dd to**. We'd built vanilla vendor U-Boot without that patch.
  - Additionally, vanilla `BOOT_TARGET_DEVICES` lists only QEMU and boots via bespoke env scripts
    (`loadknl`/`loaddtb` + EEPROM DTB detection), not extlinux — so it would never read our
    `extlinux.conf` even with `001`. Armbian's `002` (mmc boot target + kernel/fdt/ramdisk load addrs)
    and `004` (syslinux/extlinux) fix that.
  - **Fix:** switch the U-Boot input to Armbian's exact source (`pyavitz/spacemit-u-boot` @
    `k1-bl-v2.2.9-release`) and apply Armbian's patch set (001,002,003,004,007,008,009; 005/006 are
    OrangePi-only), vendored under `nix/pkgs/u-boot/patches/`. The MBR + raw-offset image layout is
    unchanged (it already matches the patch's 0x500/0x800 fallback). OpenSBI kept as-is (it builds and
  is loaded by offset). Rebuilding U-Boot + image; reflash + retest pending.
- **2026-06-15** — Patched U-Boot built cleanly (GCC 15, no issues on the pyavitz tree; all 7 patches
  applied). Rebuilt the image; new `u-boot.itb` is 2,379,974 B (vs 2.0 MB before) and verified at
  sector 2048; MBR + partitions unchanged. Awaiting reflash + serial capture. With `001`'s `BPI:`/
  `K1X:` SPL debug prints enabled, even a partial boot should now narrate how far the SPL gets.
- **2026-06-15** — Reflashed patched image. **It boots!** Serial captured cleanly via
  `stty 115200 raw` + `cat` / `picocom -b 115200` (the earlier "garble" was minicom not actually
  applying 115200 — 115200 is correct). Boot chain observed:
  `try sd... -> U-Boot SPL 2022.10 Armbian -> DDR LPDDR4X 2400MT/s -> loads fit (opensbi+uboot) ->
  U-Boot 2022.10 (Model: spacemit k1-x deb1, DRAM 8192 MB) -> MMC/PCIe(Gen2-x2)/eth ->
  Retrieving /extlinux/extlinux.conf -> NixOS menu -> loads initrd + kernel Image 7.0.12`.
  (Aside: "8 GB" on the label is the **RAM**, which trained fine — not eMMC.)
  Then it stalls: **`bootarg overflow 262+0+0+1 > 256`** — the vendor U-Boot caps the kernel cmdline
  at 256 bytes and our APPEND (long `init=/nix/store/...` + root=fstab/loglevel/lsm + our params) was
  262. Falls through to NVMe (absent) -> `=>` prompt. **Fix:** trimmed `boot.kernelParams` (dropped
  `console=tty1`, `root=UUID=`, `rootfstype=ext4` — redundant since the initrd mounts root by the
  NIXOS_SD label) to get well under 256. Rebuilding image; reflash + retest pending.
  (Future hardening: raise the U-Boot 256-byte bootargs cap so long cmdlines can't regress this.)
- **2026-06-15** — Trimmed-cmdline image (APPEND now 186 B) **boots into the kernel + initrd!**
  extlinux hands off, kernel + systemd-initrd come up. New stall: initrd times out on
  `/dev/disk/by-label/NIXOS_SD` → emergency mode (and the locked emergency console blocked debugging).
  Checked the built kernel config: K1 host drivers are builtin (`MMC_SDHCI_OF_K1=y`, `SPACEMIT_K1_CCU=y`,
  pinctrl/gpio =y) but **`MMC_BLOCK=m`** — the block layer that creates `/dev/mmcblk*` is a module and
  udev didn't autoload it in the initrd, so no block device → no root. **Fix (no kernel rebuild):**
  `boot.initrd.kernelModules = [ "mmc_block" ]` to force-load it; plus
  `boot.initrd.systemd.emergencyAccess = true` and `boot.consoleLogLevel = 7` so any further failure
  drops to a usable root shell with `dmesg`. Rebuilding initrd + image; reflash + retest pending.
- **2026-06-15** — `mmc_block` force-load worked (eMMC `mmcblk0` now enumerates, emergency shell now
  accessible) but **root still not found**. Emergency-shell `cat /proc/partitions` shows ONLY
  `mmcblk0` (+boot0/boot1/rpmb = eMMC, ~29 GiB) — **no SD-card block device, no /dev/disk/by-label**.
  Decompiled the shipped `k1-bananapi-f3.dtb`: it has **only `mmc@d4281000` (eMMC)**; the SD-card slot
  controller **`mmc@d4280000` (SDH0) is absent from the mainline DTS** (true in 7.0.12 and the 7.1
  tree — `k1.dtsi` defines only `emmc`). So mainline supports K1 eMMC but not the BPI-F3 removable SD
  slot; U-Boot reads SD via its own DTB, but the kernel has no node to bind. **Root cause of root
  timeout.** User chose: re-add the SD slot via a **DT overlay**.
  **Fix:** `hardware.deviceTree.overlays` adds `mmc@d4280000` under `/soc/storage-bus`, mirroring the
  working eMMC node (`spacemit,k1-sdhci`) but with SDH0 clocks/resets (`CLK_SDH0`/`RESET_SDH0` from
  `spacemit,k1-syscon.h`), IRQ 99, `bus-width=4`, `broken-cd`. No pinctrl/regulator yet (eMMC works
  without them; U-Boot already powered/muxed the slot) — add if the card still isn't detected.
  Rebuilding DTB+image (no kernel rebuild); reflash + retest pending.
- **2026-06-16** — Overlay didn't apply at first: NixOS `apply_overlays.py` skips an overlay whose root
  `compatible` doesn't intersect the base DTB's. **Fix:** added `compatible = "bananapi,bpi-f3",
  "spacemit,k1";` to the overlay root. Verified the rebuilt DTB now has **both** `mmc@d4280000` (SD,
  status okay) and `mmc@d4281000` (eMMC, status okay). Built full image; reflash + retest pending —
  expecting the SD card to enumerate and root to mount.
- **2026-06-16** — Overlay applied, but the kernel **panicked** in `spacemit_sdhci_set_uhs_signaling`
  (load access fault reading `SDHCI_HOST_CONTROL2` @0x3E). That `VDD_180` write only runs when the
  node is NOT `no-sdio`; the eMMC node sets `no-sd`/`no-sdio` and skips it. **Fix:** mark the SD slot
  `no-mmc; no-sdio; no-1-8-v;` (correct for an SD-card slot, and avoids the faulting path).
  (Also: `#` comments in the overlay broke the cpp/dtc parse — DTS comments must be `//`.)
- **2026-06-16** — SD card then **enumerated** (`mmc0: new high speed SDXC card`, `mmcblk0 119 GiB`,
  `NIXOS_SD` found, ext4 mounted) but **read-only** → `/sysroot/run` failed → emergency. The microSD
  slot has no write-protect tab but the controller's WP sense reads "protected". **Fix:** `disable-wp;`.
- **2026-06-16** — ✅✅ **FULL BOOT.** Reflashed; NixOS boots to `bpi-f3 login:` on hardware. Root mounts
  **r/w**, switch-root + first-boot activation succeed. Working: both GbE (`k1_emac`, RTL8211F), NVMe
  over PCIe, USB2/3 hubs, SSH daemon. Login `bpi`/`bpi-f3`.
  Cleanup: `CONFIG_LOCALVERSION=" NixOS"` (U-Boot banner now reads "NixOS" not "Armbian"); removed the
  `initcall_debug`/`consoleLogLevel=7` debug params (kept the working `earlycon=uart8250` + the SD
  overlay + `mmc_block` force-load + `emergencyAccess`).
