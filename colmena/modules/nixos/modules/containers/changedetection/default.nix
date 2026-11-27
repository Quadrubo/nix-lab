{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.changedetection;
in
{
  options.myServices.changedetection = {
    enable = mkEnableOption "changedetection.io";

    image = mkOption {
      type = types.str;
      default = "dgtlmoon/changedetection.io:0.60.10"; # renovate: docker
    };

    browserImage = mkOption {
      type = types.str;
      default = "dgtlmoon/sockpuppetbrowser:0.0.5"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for changedetection.io.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };

    timeZone = mkOption {
      type = types.str;
      default = "Europe/Berlin";
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = [
      {
        name = "changedetection.io";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.podman = {
      enable = true;
      networks = [
        { name = "changedetection"; }
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/changedetection 0755 container-user users -"
      "d /mnt/storage/containers/changedetection/datastore 0755 container-user users -"
    ];

    # Headless Chrome for JS-rendered pages / bot-protected shops
    virtualisation.oci-containers.containers.changedetection-browser = {
      image = cfg.browserImage;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=changedetection"
        "--cap-add=SYS_ADMIN"
      ];

      environment = {
        SCREEN_WIDTH = "1920";
        SCREEN_HEIGHT = "1024";
        SCREEN_DEPTH = "16";
        MAX_CONCURRENT_CHROME_PROCESSES = "4";
      };
    };

    # App
    virtualisation.oci-containers.containers.changedetection = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=changedetection"
      ];

      environment = {
        TZ = cfg.timeZone;
        BASE_URL = "https://${cfg.domain}";
        PLAYWRIGHT_DRIVER_URL = "ws://changedetection-browser:3000";
        HIDE_REFERER = "true";
      };

      volumes = [
        "/mnt/storage/containers/changedetection/datastore:/datastore"
      ];

      dependsOn = [ "changedetection-browser" ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.changedetection.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.changedetection.entrypoints" = "websecure";
          "traefik.http.routers.changedetection.tls.certresolver" = "myresolver";
          "traefik.http.services.changedetection.loadbalancer.server.port" = "5000";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.changedetection-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.changedetection.middlewares" = "changedetection-allowlist@docker";
        };
    };

    systemd.services."podman-changedetection-browser".after = [
      "podman-network-changedetection-container-user.service"
    ];
    systemd.services."podman-changedetection-browser".requires = [
      "podman-network-changedetection-container-user.service"
    ];

    systemd.services."podman-changedetection".after = [
      "podman-network-changedetection-container-user.service"
      "podman-changedetection-browser.service"
    ];
    systemd.services."podman-changedetection".requires = [
      "podman-network-changedetection-container-user.service"
      "podman-changedetection-browser.service"
    ];
  };
}
