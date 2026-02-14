{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.crowdsec;

  # Create the acquis.yaml file
  acquisFile = pkgs.writeText "acquis.yaml" ''
    filenames:
     - /var/log/auth.log
     - /var/log/syslog
    labels:
      type: syslog
    ---
    filenames:
      - /var/log/traefik/*.log
    labels:
      type: traefik
  '';

in
{
  options.myServices.crowdsec = {
    enable = mkEnableOption "CrowdSec";

    image = mkOption {
      type = types.str;
      default = "crowdsecurity/crowdsec:v1.7.3";
    };

    collections = mkOption {
      type = types.listOf types.str;
      default = [
        "crowdsecurity/traefik"
        "crowdsecurity/http-cve"
        "crowdsecurity/appsec-generic-rules"
        "crowdsecurity/appsec-virtual-patching"
        "crowdsecurity/sshd"
        "crowdsecurity/linux"
        "crowdsecurity/base-http-scenarios"
      ];
      description = "List of CrowdSec collections to install";
    };

    parsers = mkOption {
      type = types.listOf types.str;
      # TODO: remove nextcloud from defaults
      default = [ "crowdsecurity/nextcloud-whitelist" ];
      description = "List of CrowdSec parsers to install";
    };

    gid = mkOption {
      type = types.int;
      default = 100;
      description = "Group ID for CrowdSec container";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [ "crowdsec" ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/crowdsec/data 0755 container-user users -"
      "d /mnt/storage/containers/crowdsec/etc 0755 container-user users -"
    ];

    # Container
    virtualisation.oci-containers.containers.crowdsec = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--network=traefik"
      ];

      podman.user = "container-user";

      ports = [
        "127.0.0.1:9876:8080" # Local API for bouncers
      ];

      environment = {
        GID = toString cfg.gid;
        COLLECTIONS = concatStringsSep " " cfg.collections;
        PARSERS = concatStringsSep " " cfg.parsers;
      };

      volumes = [
        # CrowdSec data and configuration
        "/mnt/storage/containers/crowdsec/data:/var/lib/crowdsec/data"
        "/mnt/storage/containers/crowdsec/etc:/etc/crowdsec"

        # Mount generated acquis.yaml
        "${acquisFile}:/etc/crowdsec/acquis.yaml:ro"

        # Log sources
        "/mnt/storage/containers/traefik/logs:/var/log/traefik:ro"

        # System logs (optional - uncomment if needed)
        # "/var/log/auth.log:/var/log/auth.log:ro"
        # "/var/log/syslog:/var/log/syslog:ro"
      ];
    };

    systemd.services."podman-crowdsec".after = [ "podman-network-traefik.service" ];
    systemd.services."podman-crowdsec".requires = [ "podman-network-traefik.service" ];
  };
}
