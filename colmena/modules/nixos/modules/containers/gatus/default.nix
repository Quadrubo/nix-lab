{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.gatus;

  # Build Gatus YAML config from Nix
  gatusConfig =
    {
      storage = {
        type = "sqlite";
        path = "/data/gatus.db";
      };

      web = {
        port = 8080;
      };

      endpoints = map (
        ep:
        {
          name = ep.name;
          url = ep.url;
          interval = ep.interval;
          conditions = ep.conditions;
        }
        // optionalAttrs (ep.group != "") {
          group = ep.group;
        }
        // optionalAttrs (ep.client != { }) {
          client = ep.client;
        }
        // optionalAttrs (ep.alerts != [ ]) {
          alerts = ep.alerts;
        }
        // optionalAttrs (ep.alerts == [ ] && cfg.alerting.ntfy.enable) {
          alerts = [ { type = "ntfy"; } ];
        }
      ) cfg.endpoints;
    }
    // optionalAttrs cfg.basicAuth.enable {
      security = {
        basic = {
          username = "\${GATUS_USERNAME}";
          password-bcrypt-base64 = "\${GATUS_PASSWORD_BCRYPT_BASE64}";
        };
      };
    }
    // optionalAttrs cfg.alerting.ntfy.enable {
      alerting = {
        ntfy = {
          topic = cfg.alerting.ntfy.topic;
          url = cfg.alerting.ntfy.url;
          priority = cfg.alerting.ntfy.priority;
          token = "\${NTFY_TOKEN}";
          default-alert = {
            enabled = true;
            failure-threshold = cfg.alerting.ntfy.failureThreshold;
            success-threshold = cfg.alerting.ntfy.successThreshold;
            send-on-resolved = true;
          };
        };
      };
    };

  configFile = pkgs.writeText "gatus-config.yaml" (builtins.toJSON gatusConfig);
in
{
  options.myServices.gatus = {
    enable = mkEnableOption "Gatus";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/twin/gatus:v5.35.0"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Gatus.";
    };

    endpoints = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "Monitoring endpoints. Typically injected from flake-level allMonitoringEndpoints.";
    };

    dns = mkOption {
      type = types.str;
      default = "";
      description = "DNS server for the container (e.g. AdGuard Home IP for resolving internal domains).";
    };

    hostOverrides = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Domains to resolve to host-gateway (for services on the same host as Gatus).";
      example = [ "gatus.r.qudr.de" "julweb.dev" ];
    };

    basicAuth = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable basic auth for the Gatus dashboard.";
      };
    };

    alerting = {
      ntfy = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable ntfy alerting.";
        };

        url = mkOption {
          type = types.str;
          default = "";
          description = "ntfy server URL.";
        };

        topic = mkOption {
          type = types.str;
          default = "gatus";
          description = "ntfy topic for alerts.";
        };

        priority = mkOption {
          type = types.int;
          default = 4;
          description = "ntfy notification priority (1-5).";
        };

        failureThreshold = mkOption {
          type = types.int;
          default = 1;
          description = "Number of consecutive failures before alerting.";
        };

        successThreshold = mkOption {
          type = types.int;
          default = 2;
          description = "Number of consecutive successes before resolving.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = [
      {
        name = "Gatus";
        group = "Publy - External";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.podman = {
      enable = true;
      networks = [
        { name = "gatus"; }
      ];
    };

    sops.secrets."gatus_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "gatus_env";
      owner = "container-user";
      restartUnits = [
        "podman-gatus.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/gatus 0755 container-user users -"
      "d /mnt/storage/containers/gatus/data 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.gatus = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=gatus"
      ]
      ++ optional (cfg.dns != "") "--dns=${cfg.dns}"
      ++ map (domain: "--add-host=${domain}:host-gateway") cfg.hostOverrides;

      environmentFiles = [ config.sops.secrets."gatus_env".path ];

      volumes = [
        "${configFile}:/config/config.yaml:ro"
        "/mnt/storage/containers/gatus/data:/data"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.gatus.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.gatus.entrypoints" = "websecure";
        "traefik.http.routers.gatus.tls.certresolver" = "myresolver";
        "traefik.http.services.gatus.loadbalancer.server.port" = "8080";
      };
    };

    systemd.services."podman-gatus".after = [ "podman-network-gatus-container-user.service" ];
    systemd.services."podman-gatus".requires = [ "podman-network-gatus-container-user.service" ];
  };
}
