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

      providers = {
        docker = {
          endpoint = "unix:///var/run/docker.sock";
          exposedByDefault = false;
          network = "traefik";
        };

        file = {
          filename = "/config/dynamic.yml";
          watch = true;
        };
      };

      # Dashboard on 8080 (localhost only)
      api.insecure = true;
      log.level = "INFO";

      certificatesResolvers = {
        myresolver = {
          acme = {
            email = "ssl@julweb.dev";
            storage = "/letsencrypt/acme.json";
            # Use dnsChallenge or tlsChallenge based on config
            ${if cfg.dnsChallenge.enable then "dnsChallenge" else "tlsChallenge"} =
              if cfg.dnsChallenge.enable then
                {
                  provider = cfg.dnsChallenge.provider;
                  resolvers = cfg.dnsChallenge.resolvers;
                }
              else
                true;
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

  dynamicConfig = pkgs.writeText "dynamic.yml" (
    builtins.toJSON (
      let
        httpCfg = {
          http = {
            serversTransports = if cfg.serversTransports != { } then cfg.serversTransports else null;
          };
        };
      in
      lib.optionalAttrs (httpCfg.http.serversTransports != null) httpCfg
    )
  );
in
{
  options = {
    myServices.traefik = {
      enable = mkEnableOption "Traefik";

      image = mkOption {
        type = types.str;
        default = "traefik:v3.6.9"; # renovate: docker
      };

      dnsChallenge = {
        enable = mkEnableOption "Use DNS Challenge for certificate generation";

        provider = mkOption {
          type = types.str;
          default = "cloudflare";
          description = "DNS provider name (e.g., cloudflare, ovh, route53, etc.)";
        };

        resolvers = mkOption {
          type = types.listOf types.str;
          default = [
            "1.1.1.1:53"
            "8.8.8.8:53"
          ];
          description = "DNS resolvers to use for DNS challenge";
        };

        sopsFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to the sops file containing DNS provider credentials";
        };
      };

      serversTransports = mkOption {
        type = types.attrs;
        default = { };
        description = "Additional Traefik serversTransports configuration.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Setup sops secret if DNS challenge is enabled
    sops.secrets."traefik_dns_challenge_env" =
      mkIf (cfg.dnsChallenge.enable && cfg.dnsChallenge.sopsFile != null)
        {
          sopsFile = cfg.dnsChallenge.sopsFile;
          format = "yaml";
          key = "traefik_dns_challenge_env";
          owner = "container-user";
          restartUnits = [ "podman-traefik.service" ];
        };

    myServices.podman = {
      enable = true;
      networks = [
        { name = "traefik"; }
      ];
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
        "${dynamicConfig}:/config/dynamic.yml:ro"
        "/mnt/storage/containers/traefik/letsencrypt:/letsencrypt"
        "/mnt/storage/containers/traefik/logs:/logs"
      ];

      # Add environment file if DNS challenge is enabled
      environmentFiles = mkIf (cfg.dnsChallenge.enable && cfg.dnsChallenge.sopsFile != null) [
        config.sops.secrets."traefik_dns_challenge_env".path
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
