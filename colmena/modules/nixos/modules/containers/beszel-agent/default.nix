{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.beszel-agent;
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
        default = "henrygd/beszel-agent:0.18.2";
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
    };
  };

  config = mkIf cfg.enable {
    sops.secrets."beszel_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "beszel_env";
      owner = "container-user";
      restartUnits = [ "podman-beszel-agent.service" ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/beszel-agent/var/lib/beszel-agent 0755 container-user users -"
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
      ];

      # TODO: figure out smart data once servy is using this config
      # https://beszel.dev/guide/smart-data

      podman = {
        user = "container-user";
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
