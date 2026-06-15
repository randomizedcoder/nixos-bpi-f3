# Default user and hostname for the BPI-F3 image.
#
# The default login is user `bpi` / password `bpi-f3` (yescrypt hash below).
# CHANGE THIS before exposing the board to any network you don't trust.
let
  username = "bpi";
  hostname = "bpi-f3";
  # `mkpasswd -m yescrypt bpi-f3`
  hashedPassword = "$y$j9T$FswXaPHS5ES2MQdjZbQVC/$nuU8UvlPYXYOGgwFb2bF4zm0ZYuWugW2gzoyE8tUoL0";
in
{
  networking.hostName = hostname;

  users.users."${username}" = {
    inherit hashedPassword;
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [ "users" "networkmanager" "wheel" ];
  };
}
