{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../modules/nixos/default.nix
  ];

  boot.loader.grub.enable = true;

  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOIyANbVLEpwzS/2D5eNU40mOIuOOqTcJFUr3LY0+xt julian@nixos"
  ];

  system.stateVersion = "25.11";

  firewall = {
    enable = true;

    tcpPorts = [
      22
    ];
  };
}
