{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.bitwarden-backup;
in
{
  options.myServices.bitwarden-backup = {
    enable = mkEnableOption "Bitwarden Backup";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to the sops file containing secrets";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/quadrubo/bitwarden-backup:v0.4.2"; # renovate: docker
    };

    backupPath = mkOption {
      type = types.str;
      default = "/mnt/storage/backups/bitwarden";
      description = "Host path where backups will be stored";
    };

    bwServer = mkOption {
      type = types.str;
      default = "https://vault.bitwarden.com";
      description = "Bitwarden server URL";
    };

    backupFormat = mkOption {
      type = types.str;
      default = "encrypted_json";
      description = "Backup format (encrypted_json, json, csv)";
    };

    cronSchedule = mkOption {
      type = types.str;
      default = "0 1 * * *";
      description = "Cron schedule for backups (daily at 1 AM by default)";
    };

    tz = mkOption {
      type = types.str;
      default = "Europe/Berlin";
      description = "Timezone for the container";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        {
          name = "bitwarden-backup";
        }
      ];
    };

    # Secrets
    sops.secrets."bitwarden-backup_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "bitwarden-backup_env";
      owner = "container-user";
      restartUnits = [ "podman-bitwarden-backup.service" ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d ${cfg.backupPath} 0755 container-user users -"
    ];

    # Container
    virtualisation.oci-containers.containers.bitwarden-backup = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=bitwarden-backup"
      ];

      environment = {
        BACKUP_PATH = "/backup";
        BW_BINARY = "/usr/local/bin/bw";
        BW_SERVER = cfg.bwServer;
        BACKUP_FORMAT = cfg.backupFormat;
        CRON_SCHEDULE = cfg.cronSchedule;
        TZ = cfg.tz;
        NTFY_SERVER = "https://ntfy.r.qudr.de";
        NTFY_TOPIC = "backups";
        NTFY_USERNAME = "bitwarden-backup";
      };

      environmentFiles = [ config.sops.secrets."bitwarden-backup_env".path ];

      volumes = [
        "${cfg.backupPath}:/backup"
      ];
    };

    systemd.services."podman-bitwarden-backup".after = [
      "podman-registry-login-ghcr.service"
      "podman-network-bitwarden-backup-container-user.service"
    ];
    systemd.services."podman-bitwarden-backup".requires = [
      "podman-registry-login-ghcr.service"
      "podman-network-bitwarden-backup-container-user.service"
    ];
  };
}
