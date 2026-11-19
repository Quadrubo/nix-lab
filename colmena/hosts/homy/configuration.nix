{ ... }:
{
  imports = [
    ../../modules/nixos/default.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # Disable ZFS, which the sd-image module enables for installer images
  # because its kernel module for the Pi kernel isn't in any cache
  boot.supportedFilesystems.zfs = false;

  zramSwap.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  system.stateVersion = "26.05";

  nix.settings = {
    trusted-users = [
      "root"
      "colmena"
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  # General Settings
  users.users.colmena = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOIyANbVLEpwzS/2D5eNU40mOIuOOqTcJFUr3LY0+xt julian@nixos" # compy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOBhaJ29X++P+Ceu01qSdMeQcjviiG4rIL/GHJRorJ9 julian@nixos" # framy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5KNuNmb6r4l7wDsebVHvEbahtqTkssU8KB7t1u9bGY julian@nixos" # work
    ];
  };

  users.users.julian = {
    isNormalUser = true;
    uid = 1002;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOIyANbVLEpwzS/2D5eNU40mOIuOOqTcJFUr3LY0+xt julian@nixos" # compy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOBhaJ29X++P+Ceu01qSdMeQcjviiG4rIL/GHJRorJ9 julian@nixos" # framy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5KNuNmb6r4l7wDsebVHvEbahtqTkssU8KB7t1u9bGY julian@nixos" # work
    ];
  };

  # Allow passwordless sudo for julian
  security.sudo.extraRules = [
    {
      users = [
        "julian"
        "colmena"
      ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  time.timeZone = "Europe/Berlin";

  networking.firewall.enable = true;

  console.keyMap = "de";

  myModules.maintenance.enable = true;
  boot.loader.generic-extlinux-compatible.configurationLimit = 10;
}
