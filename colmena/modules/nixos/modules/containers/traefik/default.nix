{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.traefik;

  staticConfig = pkgs.writeText "static.yml" (
    builtins.toJSON {
      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entryPoint = {
            to = "websecure";
            scheme = "https";
          };
        };
        websecure.address = ":443";
      };

      providers.docker = {
        endpoint = "unix:///var/run/docker.sock";
        exposedByDefault = false;
        network = "traefik";
      };

      # TODO: Dashboard on 8080 (localhost only)
      api.insecure = true;
      log.level = "INFO";

      certificatesResolvers = {
        myresolver = {
          acme = {
            email = "ssl@julweb.dev";
            storage = "/letsencrypt/acme.json";
            # TODO: use dnsChallenge for homeservers
            tlsChallenge = true;
          };
        };
      };

      accessLog = {
        filePath = "/logs/traefik.log";
        format = "json";
        filters = {
          statusCodes = [
            "200-299"
            "400-599"
          ];
        };
        bufferingSize = 0;
        fields = {
          headers = {
            defaultMode = "drop";
            names = {
              "User-Agent" = "keep";
            };
          };
        };
      };

      # TODO: make optional
      experimental = {
        plugins = {
          bouncer = {
            moduleName = "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin";
            version = "v1.3.5";
          };
        };
      };
    }
  );
in
{
  options = {
    myServices.traefik = {
      enable = mkEnableOption "Traefik";

      image = mkOption {
        type = types.str;
        default = "traefik:v3.6.1"; # renovate: docker
      };
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [ "traefik" ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/traefik/letsencrypt 0755 container-user users -"
      "d /mnt/storage/containers/traefik/logs 0755 container-user users -"
    ];

    # Container
    virtualisation.oci-containers.containers.traefik = {
      image = cfg.image;
      autoStart = true;

      extraOptions = [
        "--network=traefik"
      ];

      podman = {
        user = "container-user";
      };

      ports = [
        "80:80"
        "443:443"
        # Dashboard only accessible via SSH Tunnel
        "127.0.0.1:8080:8080"
      ];

      volumes = [
        "/run/user/1000/podman/podman.sock:/var/run/docker.sock:ro"
        "${staticConfig}:/config/static.yml:ro"
        "/mnt/storage/containers/traefik/letsencrypt:/letsencrypt"
        "/mnt/storage/containers/traefik/logs:/logs"
      ];

      cmd = [ "--configFile=/config/static.yml" ];
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_unprivileged_port_start" = 80;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
