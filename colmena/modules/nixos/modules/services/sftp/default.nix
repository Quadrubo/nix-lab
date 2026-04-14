{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.sftp;

  matchBlocks = concatStringsSep "\n" (
    map (account: ''
      Match User ${account.user}
        ForceCommand internal-sftp
        ChrootDirectory ${account.chrootDirectory}
        AllowTcpForwarding no
        X11Forwarding no
    '') cfg.accounts
  );
in
{
  options.myServices.sftp = {
    enable = mkEnableOption "Restricted SFTP access";

    accounts = mkOption {
      type = types.listOf (
        types.submodule (
          { config, ... }:
          {
            options = {
              name = mkOption {
                type = types.str;
                description = "Identifier for this account. Used as default for user and chroot directory.";
                example = "opnsense";
              };

              user = mkOption {
                type = types.str;
                description = "System username for the SFTP connection.";
              };

              authorizedKeys = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "SSH public keys authorized to connect as this user.";
              };

              chrootDirectory = mkOption {
                type = types.str;
                description = "Chroot directory for the SFTP session. Must be owned by root.";
                example = "/mnt/storage/backups/opnsense";
              };

              writeDirectory = mkOption {
                type = types.str;
                default = "upload";
                description = "Subdirectory inside the chroot where the user can write.";
              };
            };
          }
        )
      );
      default = [ ];
      description = "List of restricted SFTP accounts to configure.";
    };
  };

  config = mkIf (cfg.enable && cfg.accounts != [ ]) {
    services.openssh.extraConfig = matchBlocks;

    users.groups = listToAttrs (
      map (account: {
        name = account.user;
        value = { };
      }) cfg.accounts
    );

    users.users = listToAttrs (
      map (account: {
        name = account.user;
        value = {
          isNormalUser = true;
          group = account.user;
          home = "${account.chrootDirectory}/${account.writeDirectory}";
          createHome = false;
          shell = "/run/current-system/sw/bin/nologin";
          openssh.authorizedKeys.keys = account.authorizedKeys;
        };
      }) cfg.accounts
    );

    systemd.tmpfiles.rules = concatMap (account: [
      # ChrootDirectory must be owned by root
      "d ${account.chrootDirectory} 0755 root root -"
      # Write dir owned by the SFTP user
      "d ${account.chrootDirectory}/${account.writeDirectory} 0755 ${account.user} ${account.user} -"
    ]) cfg.accounts;
  };
}
