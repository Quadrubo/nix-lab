{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.pelican;

  caddyFile = pkgs.writeText "Caddyfile" ''
    {
    	admin off
    	servers {
    		trusted_proxies static 192.168.10.10
    	}
    }

    :8080 {
    	root * /var/www/html/public
    	encode gzip

    	php_fastcgi 127.0.0.1:9000 {
    		env PHP_VALUE "upload_max_filesize = 256M
                           post_max_size = 256M"
    	}
    	file_server
    }
  '';
in
{
  options.myServices.pelican = {
    enable = mkEnableOption "Pelican";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    panelDomain = mkOption {
      type = types.str;
      description = "Domain used for the Pelican panel.";
    };

    wingsDomain = mkOption {
      type = types.str;
      description = "Domain used for Pelican Wings.";
    };

    panelImage = mkOption {
      type = types.str;
      default = "ghcr.io/pelican-dev/panel:v1.0.0-beta21"; # renovate: docker
    };

    wingsImage = mkOption {
      type = types.str;
      default = "ghcr.io/pelican-dev/wings:v1.0.0-beta13"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "mariadb:12"; # renovate: docker
    };

    panelDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/pelican-panel/data";
      description = "Path to store Pelican panel data.";
    };

    panelLogsPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/pelican-panel/logs";
      description = "Path to store Pelican panel logs.";
    };

    dbDataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/pelican-db/mysql";
      description = "Path to store Pelican database data.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "pelican"; }
        { name = "wings1"; }
      ];
    };

    sops.secrets."pelican-db_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "pelican-db_env";
      owner = "container-user";
      restartUnits = [
        "podman-pelican-db.service"
      ];
    };

    sops.secrets."pelican-panel_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "pelican-panel_env";
      owner = "container-user";
      restartUnits = [
        "podman-pelican-panel.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.panelDataPath} 0755 container-user users -"
      "d ${cfg.panelLogsPath} 0755 container-user users -"
      "d ${cfg.dbDataPath} 0755 container-user users -"
      "d /etc/pelican 0755 container-user users -"
      "d /var/lib/pelican 0755 container-user users -"
      "d /var/log/pelican 0755 container-user users -"
      "d /tmp/pelican 0755 container-user users -"
    ];

    # Database
    virtualisation.oci-containers.containers.pelican-db = {
      image = cfg.dbImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=pelican"
      ];

      environment = {
        MYSQL_DATABASE = "panel";
        MYSQL_USER = "pelican";
      };

      environmentFiles = [ config.sops.secrets."pelican-db_env".path ];

      volumes = [
        "${cfg.dbDataPath}:/var/lib/mysql"
      ];
    };

    # Panel
    virtualisation.oci-containers.containers.pelican-panel = {
      image = cfg.panelImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=pelican"
      ];

      environment = {
        XDG_DATA_HOME = "/pelican-data";
        APP_URL = "https://${cfg.panelDomain}";
        TZ = "Europe/Berlin";
        APP_ENV = "production";
        DB_CONNECTION = "mariadb";
        DB_DATABASE = "panel";
        DB_HOST = "pelican-db";
        DB_PORT = "3306";
        DB_USERNAME = "pelican";
      };

      environmentFiles = [ config.sops.secrets."pelican-panel_env".path ];

      volumes = [
        "${cfg.panelDataPath}:/pelican-data"
        "${cfg.panelLogsPath}:/var/www/html/storage/logs"
        "${caddyFile}:/etc/caddy/Caddyfile:ro"
      ];

      dependsOn = [ "pelican-db" ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.pelican-panel.rule" = "Host(`${cfg.panelDomain}`)";
        "traefik.http.routers.pelican-panel.entrypoints" = "websecure";
        "traefik.http.routers.pelican-panel.tls.certresolver" = "myresolver";
        "traefik.http.routers.pelican-panel.service" = "pelican-panel";
        "traefik.http.services.pelican-panel.loadbalancer.server.port" = "8080";

      };
    };

    # Wings
    # TODO: wings currently does not work because of podman incompatibilities
    # One PR that could fix this is: https://github.com/pelican-dev/wings/pull/151
    virtualisation.oci-containers.containers.pelican-wings = {
      image = cfg.wingsImage;
      autoStart = true;

      podman.user = "container-user";

      cmd = [
        "wings"
        "--ignore-certificate-errors"
      ];

      extraOptions = [
        "--network=traefik"
        "--network=wings1"
      ];

      ports = [
        "2022:2022"
      ];

      environment = {
        TZ = "Europe/Berlin";
        APP_TIMEZONE = "Europe/Berlin";
        WINGS_UID = "1000";
        WINGS_GID = "1000";
        WINGS_USERNAME = "pelican";
      };

      volumes = [
        "/run/user/1000/podman/podman.sock:/var/run/docker.sock"
        # TODO: figure out how this works with podman
        # "/var/lib/docker/containers:/var/lib/docker/containers"
        "/etc/pelican:/etc/pelican"
        "/var/lib/pelican:/var/lib/pelican"
        "/var/log/pelican:/var/log/pelican"
        "/tmp/pelican:/tmp/pelican"
        "/etc/ssl/certs:/etc/ssl/certs:ro"
      ];

      dependsOn = [ "pelican-panel" ];

      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.pelican-wings.rule" = "Host(`${cfg.wingsDomain}`)";
        "traefik.http.routers.pelican-wings.entrypoints" = "websecure";
        "traefik.http.routers.pelican-wings.tls.certresolver" = "myresolver";
        "traefik.http.routers.pelican-wings.service" = "pelican-wings";
        "traefik.http.services.pelican-wings.loadbalancer.server.port" = "443";
      };
    };

    systemd.services."podman-pelican-db".after = [ "podman-network-pelican-container-user.service" ];
    systemd.services."podman-pelican-db".requires = [ "podman-network-pelican-container-user.service" ];

    systemd.services."podman-pelican-panel".after = [
      "podman-network-pelican-container-user.service"
      "podman-pelican-db.service"
    ];
    systemd.services."podman-pelican-panel".requires = [
      "podman-network-pelican-container-user.service"
      "podman-pelican-db.service"
    ];

    systemd.services."podman-pelican-wings".after = [
      "podman-network-wings1-container-user.service"
      "podman-pelican-panel.service"
    ];
    systemd.services."podman-pelican-wings".requires = [
      "podman-network-wings1-container-user.service"
      "podman-pelican-panel.service"
    ];
  };
}