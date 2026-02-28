{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.nextcloud;
in
{
  options.myServices.nextcloud = {
    enable = mkEnableOption "Nextcloud";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Nextcloud.";
    };

    cspHostname = mkOption {
      type = types.str;
      description = "Hostname used in Nextcloud content security policy.";
    };

    appImage = mkOption {
      type = types.str;
      default = "nextcloud:32-apache"; # renovate: docker
    };

    cronImage = mkOption {
      type = types.str;
      default = "nextcloud:32-apache"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "mariadb:10"; # renovate: docker
    };

    redisImage = mkOption {
      type = types.str;
      default = "redis:7.4.8"; # renovate: docker
    };

    htmlPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/nextcloud/html";
      description = "Path to store Nextcloud HTML data.";
    };

    dbDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/nextcloud-db/mysql";
      description = "Path to store Nextcloud database data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "nextcloud"; }
      ];
    };

    sops.secrets."nextcloud_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "nextcloud_env";
      owner = "container-user";
      restartUnits = [
        "podman-nextcloud.service"
      ];
    };

    sops.secrets."nextcloud-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "nextcloud-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-nextcloud-db.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d ${cfg.htmlPath} 0755 container-user users -"
      "d ${cfg.dbDataPath} 0755 container-user users -"
    ];

    # Database
    virtualisation.oci-containers.containers.nextcloud-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=nextcloud"
      ];

      cmd = [
        "--transaction-isolation=READ-COMMITTED"
        "--log-bin=binlog"
        "--binlog-format=ROW"
      ];

      environment = {
        MARIADB_DATABASE = "nextcloud";
        MARIADB_USER = "nextcloud";
      };

      environmentFiles = [ config.sops.secrets."nextcloud-db_env".path ];

      volumes = [
        "${cfg.dbDataPath}:/var/lib/mysql"
      ];
    };

    # Redis
    virtualisation.oci-containers.containers.nextcloud-redis = {
      image = cfg.redisImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=nextcloud"
      ];
    };

    # App
    virtualisation.oci-containers.containers.nextcloud = {
      image = cfg.appImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=nextcloud"
      ];

      environment = {
        MYSQL_HOST = "nextcloud-db";
        MYSQL_DATABASE = "nextcloud";
        MYSQL_USER = "nextcloud";
        REDIS_HOST = "nextcloud-redis";
        TRUSTED_PROXIES = "172.17.0.0/12";
        NC_maintenance_window_start = "1";
        NC_default_phone_region = "DE";
      };

      environmentFiles = [ config.sops.secrets."nextcloud_env".path ];

      volumes = [
        "${cfg.htmlPath}:/var/www/html"
      ];

      dependsOn = [
        "nextcloud-db"
        "nextcloud-redis"
      ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.nextcloud.rule" = "Host(`${cfg.domain}`)";
        "traefik.http.routers.nextcloud.entrypoints" = "websecure";
        "traefik.http.routers.nextcloud.tls.certresolver" = "myresolver";
        "traefik.http.routers.nextcloud.middlewares" = "nextcloud,nextcloud_redirect";
        "traefik.http.middlewares.nextcloud.headers.contentSecurityPolicy" = "frame-ancestors 'self' ${cfg.cspHostname} *.${cfg.cspHostname}";
        "traefik.http.middlewares.nextcloud.headers.stsSeconds" = "155520011";
        "traefik.http.middlewares.nextcloud.headers.stsIncludeSubdomains" = "true";
        "traefik.http.middlewares.nextcloud.headers.stsPreload" = "true";
        "traefik.http.middlewares.nextcloud_redirect.redirectregex.permanent" = "true";
        "traefik.http.middlewares.nextcloud_redirect.redirectregex.regex" = "https://(.*)/.well-known/(?:card|cal)dav";
        "traefik.http.middlewares.nextcloud_redirect.redirectregex.replacement" = "https://${cfg.domain}/remote.php/dav/";
      };
    };

    # Cron
    virtualisation.oci-containers.containers.nextcloud-cron = {
      image = cfg.cronImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=nextcloud"
        "--entrypoint=/cron.sh"
      ];

      volumes = [
        "${cfg.htmlPath}:/var/www/html"
      ];

      dependsOn = [
        "nextcloud-db"
        "nextcloud-redis"
      ];
    };

    systemd.services."podman-nextcloud-db".after = [ "podman-network-nextcloud-container-user.service" ];
    systemd.services."podman-nextcloud-db".requires = [ "podman-network-nextcloud-container-user.service" ];

    systemd.services."podman-nextcloud-redis".after = [ "podman-network-nextcloud-container-user.service" ];
    systemd.services."podman-nextcloud-redis".requires = [ "podman-network-nextcloud-container-user.service" ];

    systemd.services."podman-nextcloud".after = [
      "podman-network-nextcloud-container-user.service"
      "podman-nextcloud-db.service"
      "podman-nextcloud-redis.service"
    ];
    systemd.services."podman-nextcloud".requires = [
      "podman-network-nextcloud-container-user.service"
      "podman-nextcloud-db.service"
      "podman-nextcloud-redis.service"
    ];

    systemd.services."podman-nextcloud-cron".after = [
      "podman-network-nextcloud-container-user.service"
      "podman-nextcloud-db.service"
      "podman-nextcloud-redis.service"
    ];
    systemd.services."podman-nextcloud-cron".requires = [
      "podman-network-nextcloud-container-user.service"
      "podman-nextcloud-db.service"
      "podman-nextcloud-redis.service"
    ];
  };
}
