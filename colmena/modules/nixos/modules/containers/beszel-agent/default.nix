{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.beszel-agent;
  hasDevices = cfg.devices != [ ];
in
{
  options = {
    myServices.beszel-agent = {
      enable = mkEnableOption "Beszel Agent";

      sopsFile = mkOption {
        type = types.path;
      };

      image = mkOption {
        type = types.str;
        default = "henrygd/beszel-agent:0.18.4-alpine"; # renovate: docker
        description = "The docker image to run.";
      };

      port = mkOption {
        type = types.port;
        default = 45876;
        description = "Port the agent listens on.";
      };

      key = mkOption {
        type = types.str;
        description = "Public Key for the agent.";
      };

      hubUrl = mkOption {
        type = types.str;
        default = "";
        description = "URL of the Beszel Hub.";
      };

      extraFilesystems = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption { type = types.str; };
              path = mkOption { type = types.str; };
            };
          }
        );
        default = [ ];
        example = [
          {
            name = "backup-disk";
            path = "/mnt/backup";
          }
        ];
        description = "List of extra filesystems to monitor.";
      };

      devices = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [
          "/dev/sda"
          "/dev/sdb"
        ];
        description = "Block devices to pass through to Beszel. These will be used in S.M.A.R.T. monitoring. Using this option will run the container as root.";
      };
    };
  };

  config = mkIf cfg.enable {
    sops.secrets."beszel_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "beszel_env";
      owner = if hasDevices then "root" else "container-user";
      restartUnits = [ "podman-beszel-agent.service" ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/beszel-agent/var/lib/beszel-agent 0755 ${
        if hasDevices then "root" else "container-user"
      } users -"
    ];

    # Container
    virtualisation.oci-containers.containers.beszel-agent = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--health-cmd=[\"/agent\", \"health\"]"
        "--health-interval=10s"
        "--health-retries=12"
        "--network=host"
      ]
      ++ optionals hasDevices (
        [
          "--cap-add=SYS_RAWIO"
          "--cap-add=SYS_ADMIN"
        ]
        ++ map (device: "--device=${device}") cfg.devices
      );

      # TODO: also check if nvme are working, it could be necessary to mount those differently
      # it seems like they currently don't update.

      podman = {
        # TODO: create issue that S.M.A.R.T. monitoring requires running as root
        user = if hasDevices then "root" else "container-user";
        sdnotify = "healthy";
      };

      environmentFiles = [ config.sops.secrets."beszel_env".path ];

      environment = {
        PORT = toString cfg.port;
        KEY = cfg.key;
        HUB_URL = cfg.hubUrl;
        DOCKER_HOST = "unix:///run/user/1000/podman/podman.sock";
      };

      volumes = [
        "/var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket:ro"
        "/run/user/1000/podman/podman.sock:/run/user/1000/podman/podman.sock:ro"
        "/mnt/storage/containers/beszel-agent/var/lib/beszel-agent:/var/lib/beszel-agent"
      ]
      ++ (
        # Map extra filesystems dynamically
        # /mnt/disk1/.beszel -> /extra-filesystems/disk1
        map (fs: "${fs.path}/.beszel:/extra-filesystems/${fs.name}:ro") cfg.extraFilesystems
      );
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
