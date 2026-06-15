{
  description = "NixOS for the Banana Pi BPI-F3 (SpacemiT K1, RISC-V), cross-compiled from x86_64";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # SpacemiT vendor bootloader sources (non-flake). Pinned to the
    # k1-bl-v2.2.10-release tag revisions. See nix/pkgs/{u-boot,opensbi}.
    uboot-spacemit = {
      url = "git+https://gitee.com/spacemit-buildroot/uboot-2022.10.git?ref=k1-bl-v2.2.y&rev=46a4f510352684407c074b7c0e9114b5443dcc59";
      flake = false;
    };
    opensbi-spacemit = {
      url = "git+https://gitee.com/spacemit-buildroot/opensbi.git?ref=k1-bl-v2.2.y&rev=34143f5f665be8b86ebb71b8085a1ade7f8b97ad";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      crossSystemConfig = import ./nix/cross.nix;
      overlay = import ./nix/overlay.nix inputs;

      # Cross pkgset: build host x86_64-linux, target riscv64. The overlay adds
      # the bootloader packages (k1-opensbi, bpi-f3-uboot).
      pkgsCross = import nixpkgs {
        localSystem = "x86_64-linux";
        crossSystem = crossSystemConfig;
        overlays = [ overlay ];
      };
    in
    {
      overlays.default = overlay;

      nixosConfigurations.bpi-f3-cross = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            nixpkgs.crossSystem = crossSystemConfig;
            nixpkgs.overlays = [ overlay ];
          }
          ./nix/modules/bpi-f3.nix
          ./nix/modules/sd-image/sd-image-bpi-f3.nix
          ./nix/modules/user-group.nix
        ];
      };

      packages.x86_64-linux = {
        default = self.nixosConfigurations.bpi-f3-cross.config.system.build.sdImage;
        sdImage = self.nixosConfigurations.bpi-f3-cross.config.system.build.sdImage;
        uboot = pkgsCross.bpi-f3-uboot;
        opensbi = pkgsCross.k1-opensbi;
      };
    };
}
