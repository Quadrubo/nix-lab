{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.ntfy;
in
{
  options.myServices.ntfy = {
    enable = mkEnableOption "ntfy";

    domain = mkOption {
      type = types.str;
      description = "Domain used for ntfy.";
    };

    image = mkOption {
      type = types.str;
      default = "binwiederhier/ntfy:v2.17.0"; # renovate: docker
    };

    configPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/ntfy/config";
      description = "Path to store ntfy configuration.";
    };

    cachePath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/ntfy/cache";
      description = "Path to store ntfy cache.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        {
          name = "ntfy";
        }
        {
          name = "traefik";
        }
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0755 container-user users -"
      "d ${cfg.cachePath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.ntfy = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      cmd = [ "serve" ];

      extraOptions = [
        "--network=traefik"
        "--network=ntfy"
        "--health-cmd=wget -q --tries=1 http://localhost:80/v1/health -O - | grep -Eo '\"healthy\"\\s*:\\s*true' || exit 1"
        "--health-interval=60s"
        "--health-timeout=10s"
        "--health-retries=3"
        "--health-start-period=40s"
      ];

      environment = {
        NTFY_BASE_URL = "https://${cfg.domain}";
        NTFY_WEB_ROOT = "app";
        NTFY_UPSTREAM_BASE_URL = "https://ntfy.sh";
        NTFY_CACHE_FILE = "/etc/ntfy/cache.db";
        NTFY_CACHE_DURATION = "12h";
        NTFY_AUTH_FILE = "/etc/ntfy/user.db";
        NTFY_AUTH_DEFAULT_ACCESS = "deny-all";
        NTFY_ATTACHMENT_CACHE_DIR = "/config/attachments";
        NTFY_ATTACHMENT_TOTAL_SIZE_LIMIT = "5G";
        NTFY_ATTACHMENT_FILE_SIZE_LIMIT = "15M";
        NTFY_ATTACHMENT_EXPIRY_DURATION = "3h";
        NTFY_SMTP_SENDER_ADDR = "";
        NTFY_SMTP_SENDER_USER = "";
        NTFY_SMTP_SENDER_PASS = "";
        NTFY_SMTP_SENDER_FROM = "";
        NTFY_SMTP_SERVER_ADDR_PREFIX = "";
        NTFY_LOG_LEVEL = "info";
        NTFY_ENABLE_LOGIN = "true";
      };

      volumes = [
        "${cfg.cachePath}:/var/cache/ntfy"
        "${cfg.configPath}:/etc/ntfy"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.ntfy.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.ntfy.entrypoints" = "websecure";
        "traefik.http.routers.ntfy.tls.certresolver" = "myresolver";
      };
    };

    systemd.services."podman-ntfy".after = [
      "podman-network-ntfy-container-user.service"
      "podman-network-traefik-container-user.service"
    ];
    systemd.services."podman-ntfy".requires = [
      "podman-network-ntfy-container-user.service"
      "podman-network-traefik-container-user.service"
    ];
  };
}
