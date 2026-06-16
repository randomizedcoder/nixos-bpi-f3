# Base headless system config for the Banana Pi BPI-F3.
{ lib, pkgs, ... }:
{
  # Headless: serial is the primary console; disable the hvc0 getty that some
  # RISC-V profiles enable.
  systemd.services."serial-getty@hvc0".enable = false;

  services.openssh = {
    enable = lib.mkDefault true;
    settings.PasswordAuthentication = lib.mkDefault true;
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

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.11";
}
