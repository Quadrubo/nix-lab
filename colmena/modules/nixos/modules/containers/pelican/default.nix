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
      default = "ghcr.io/pelican-dev/panel:v1.0.0-beta34"; # renovate: docker
    };

    wingsImage = mkOption {
      type = types.str;
      default = "ghcr.io/pelican-dev/wings:v1.0.0-beta25"; # renovate: docker
    };

    dbImage = mkOption {
      type = types.str;
      default = "mariadb:12.3.2"; # renovate: docker
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

    dbLocalhostPort = mkOption {
      type = types.nullOr types.port;
      default = null;
      description = "When set, publish the DB port to this loopback port on the host (for borgmatic backups).";
    };

    serverPortRanges = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            from = mkOption { type = types.port; };
            to = mkOption { type = types.port; };
          };
        }
      );
      default = [
        {
          from = 25565;
          to = 25600;
        } # Minecraft Java
        {
          from = 19132;
          to = 19133;
        } # Minecraft Bedrock
      ];
      description = ''
        Port ranges opened (TCP + UDP) in the firewall for Pelican game-server
        allocations. These are raw TCP/UDP connections and bypass Traefik, so
        the host firewall must allow them (and the router must forward them for
        external players).
      '';
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = [
      {
        name = "Pelican Panel";
        group = "Servy - Internal";
        url = "https://${cfg.panelDomain}";
      }
    ];

    myServices.backups.mariadbDatabases = optional (cfg.dbLocalhostPort != null) {
      name = "panel";
      hostname = "127.0.0.1";
      port = cfg.dbLocalhostPort;
      username = "pelican";
      password = "\${PELICAN_DB_PASSWORD}";
      options = "--skip-ssl";
    };

    myServices.podman = {
      enable = true;
      networks = [
        { name = "pelican"; }
        { name = "wings1"; }
      ];
    };

    # Game-server allocations are published on the host by Wings and do NOT go
    # through Traefik (raw TCP/UDP), so the firewall must allow them. 2022 is the
    # Wings SFTP port. External players also need the router to forward these.
    networking.firewall.allowedTCPPorts = [ 2022 ];
    networking.firewall.allowedTCPPortRanges = cfg.serverPortRanges;
    networking.firewall.allowedUDPPortRanges = cfg.serverPortRanges;

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
        # Allow MariaDB time to shut down cleanly to avoid tc.log corruption
        "--stop-timeout=30"
      ];

      ports = optional (cfg.dbLocalhostPort != null) "127.0.0.1:${toString cfg.dbLocalhostPort}:3306";

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
        # The panel calls the Wings node back on its public URL (wingsDomain),
        # which resolves to the host LAN IP that a rootless container can't reach.
        # Pin it to the host gateway: panel -> haproxy -> Traefik -> wings.
        # The node's "Connect" port must be 443 (not Wings' 8080 default) to match.
        "--add-host=${cfg.wingsDomain}:host-gateway"
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
        # Behind Traefik: skip the entrypoint's Let's Encrypt email requirement
        # (the panel does not terminate TLS itself).
        BEHIND_PROXY = "true";
      };

      environmentFiles = [ config.sops.secrets."pelican-panel_env".path ];

      # The panel image runs entirely as www-data (uid 82), which under rootless
      # Podman maps to a subuid that can't write the bind mounts. ":U" makes
      # Podman chown the mount sources to the mapped uid on start. ZFS can't do
      # idmapped mounts, so keep-id would force a full layer copy - ":U" avoids that.
      volumes = [
        "${cfg.panelDataPath}:/pelican-data:U"
        "${cfg.panelLogsPath}:/var/www/html/storage/logs:U"
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
    # Runs against the rootless Podman socket (mounted as the docker socket below).
    # cgroup v2 caveat: the per-container OOM killer cannot be disabled, so game
    # servers must be created with the OOM killer ENABLED in the panel. Otherwise
    # Wings passes OomKillDisable=true and the container fails to start.
    # Upstream fix that would make Wings handle this automatically is still open:
    # https://github.com/pelican-dev/wings/pull/151
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
        # Wings calls the panel back on its public URL (panelDomain). That URL
        # resolves to the host LAN IP, which a rootless container can't reach
        # (pasta won't hairpin to the host's own address). Pin it to the host
        # gateway instead so the request goes host -> haproxy -> Traefik -> panel.
        "--add-host=${cfg.panelDomain}:host-gateway"
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
