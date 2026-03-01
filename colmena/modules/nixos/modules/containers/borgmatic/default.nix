{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.borgmatic;

  crontabFile = pkgs.writeText "crontab.txt" ''
    ${cfg.cronSchedule} PATH=$PATH:/usr/local/bin /usr/local/bin/borgmatic --stats -v 0 2>&1
  '';

  configFile = pkgs.writeText "config.yaml" (
    builtins.toJSON {
      source_directories = cfg.sourceDirectories;
      mariadb_databases = cfg.mariadbDatabases;
      repositories = cfg.repositories;

      one_file_system = true;
      ssh_command = cfg.sshCommand;

      compression = "lz4";
      archive_name_format = "backup-{now}";

      keep_hourly = 2;
      keep_daily = 7;
      keep_weekly = 4;
      keep_monthly = 12;
      keep_yearly = 10;

      relocated_repo_access_is_ok = true;

      checks = [
        { name = "repository"; }
        { name = "archives"; }
      ];
      check_last = 3;

      before_backup = [ "echo 'Starting a backup job.'" ];
      after_backup = [ "echo 'Backup created.'" ];
      on_error = [ "echo 'Error while creating a backup.'" ];

      ntfy = {
        topic = "borgmatic";
        server = "https://ntfy.r.qudr.de";
        username = "borgmatic";
        # Read password from environment variable for security
        password = "\${BORGMATIC_NTFY_PASSWORD}";

        start = {
          title = "[${cfg.hostname}] A borgmatic backup started";
          message = "Watch this space...";
          tags = "borgmatic";
          priority = "min";
        };
        finish = {
          title = "[${cfg.hostname}] A borgmatic backup completed successfully";
          message = "Nice!";
          tags = "borgmatic,+1";
          priority = "min";
        };
        fail = {
          title = "[${cfg.hostname}] A borgmatic backup failed";
          message = "You should probably fix this";
          tags = "borgmatic,-1,skull";
          priority = "max";
        };
        states = [
          "start"
          "finish"
          "fail"
        ];
      };
    }
  );
in
{
  options.myServices.borgmatic = {
    enable = mkEnableOption "Borgmatic";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/borgmatic-collective/borgmatic:2.1"; # renovate: docker
    };

    hostname = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Hostname to use in notifications";
    };

    cronSchedule = mkOption {
      type = types.str;
      default = "0 3 * * *";
      description = "Cron schedule for the backup";
    };

    repositories = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "List of backup repositories";
    };

    sourceDirectories = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of directories to backup";
    };

    mariadbDatabases = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "List of MariaDB databases to backup (name, hostname, username, password)";
    };

    sshCommand = mkOption {
      type = types.str;
      default = "ssh";
      description = "SSH command to use";
    };

    networks = mkOption {
      type = types.listOf (types.submodule ({ ... }: {
        options = {
          name = mkOption {
            type = types.str;
            description = "Podman network name.";
          };
          user = mkOption {
            type = types.str;
            default = "container-user";
            description = "User that owns the rootless network.";
          };
          group = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Group used for the network unit, if needed.";
          };
        };
      }));
      default = [ { name = "borgmatic"; } ];
      description = "Additional networks to connect to (e.g., for database backups)";
    };

    additionalVolumes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional volumes to mount for backup sources";
      example = [ "/path/on/host:/path/in/container:ro" ];
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = cfg.networks;
    };

    # Secrets
    sops.secrets."borgmatic_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "borgmatic_env";
      owner = "container-user";
      restartUnits = [ "podman-borgmatic.service" ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/borg-repository 0755 container-user users -"
      "d /mnt/storage/containers/borgmatic/config 0755 container-user users -"
      "d /mnt/storage/containers/borgmatic/state 0755 container-user users -"
      "d /mnt/storage/containers/borgmatic/keys 0755 container-user users -"
      "d /mnt/storage/containers/borgmatic/ssh-keys 0755 container-user users -"
      "d /mnt/storage/containers/borgmatic/cache 0755 container-user users -"
    ];

    # Container
    virtualisation.oci-containers.containers.borgmatic = {
      image = cfg.image;
      autoStart = true;

      extraOptions = lib.flatten [
        (map (net: "--network=${net.name}") cfg.networks)
        [ "--device=/dev/fuse" ]
      ];

      podman.user = "container-user";

      capabilities = {
        SYS_ADMIN = true;
      };

      environmentFiles = [ config.sops.secrets."borgmatic_env".path ];

      volumes = lib.flatten [
        # Configuration files
        [
          "${configFile}:/etc/borgmatic.d/config.yaml:ro"
          "${crontabFile}:/etc/borgmatic.d/crontab.txt:ro"
        ]
        # Core borgmatic directories
        [
          "/boot:/boot:ro"
          "/mnt/storage/borg-repository:/mnt/borg-repository"
          "/mnt/storage/containers/borgmatic/config:/etc/borgmatic.d"
          "/mnt/storage/containers/borgmatic/state:/root/.borgmatic"
          "/mnt/storage/containers/borgmatic/keys:/root/.config/borg"
          "/mnt/storage/containers/borgmatic/ssh-keys:/root/.ssh"
          "/mnt/storage/containers/borgmatic/cache:/root/.cache/borg"
          "/mnt/storage:/mnt/storage:ro"
        ]
        # Additional volumes
        cfg.additionalVolumes
      ];
    };

    systemd.services."podman-borgmatic" = mkMerge [
      (mkIf (cfg.networks != [ ]) {
        after = map (net: "podman-network-${net.name}-${net.user}.service") cfg.networks;
        requires = map (net: "podman-network-${net.name}-${net.user}.service") cfg.networks;
      })
    ];
  };
}
