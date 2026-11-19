{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.homeassistant;

  allowlistIps = concatMap (g: config.myServices.traefik.allowlistGroups.${g}) cfg.allowlistGroups;

  # Write the initial config once, since HA owns the file afterwards
  initialConfig = pkgs.writeText "configuration.yaml" ''
    default_config:

    automation: !include automations.yaml
    script: !include scripts.yaml
    scene: !include scenes.yaml
  '';
in
{
  options.myServices.homeassistant = {
    enable = mkEnableOption "Home Assistant";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/home-assistant/home-assistant:2026.11.0"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Home Assistant.";
    };

    configPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/homeassistant/config";
      description = "Path to store the Home Assistant configuration.";
    };

    customComponents = mkOption {
      type = types.attrsOf types.path;
      default = { };
      description = "Custom integrations mounted read-only into /config/custom_components/<name>.";
    };

    monitoring = mkOption {
      type = types.bool;
      default = true;
      description = "Add a Gatus endpoint for Home Assistant (myServices.monitoring.endpoints).";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = mkIf cfg.monitoring [
      {
        name = "Home Assistant";
        group = "Homy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.podman.enable = true;

    # Directories
    systemd.tmpfiles.rules = [
      "d ${cfg.configPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.homeassistant = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        # Use the host network, since discovery (mDNS, SSDP, Cast, DLNA) doesn't
        # reach a container in a service network
        "--network=host"
      ];

      environment = {
        TZ = config.time.timeZone;
      };

      volumes = [
        "${cfg.configPath}:/config"
      ]
      ++ mapAttrsToList (name: src: "${src}:/config/custom_components/${name}:ro") cfg.customComponents;
    };

    # Route through Traefik's file provider, since its Docker provider can't
    # reach a container on the host network. Home Assistant rejects proxied
    # requests until the onboarding at http://<host>:8123 is done and Settings >
    # System > Network trusts 127.0.0.1, ::1 and the host's LAN address as proxies
    myServices.traefik.dynamicHttp = {
      routers.homeassistant = {
        rule = "Host(`${cfg.domain}`)";
        entryPoints = [ "websecure" ];
        tls.certResolver = "myresolver";
        service = "homeassistant";
      }
      // optionalAttrs (allowlistIps != [ ]) {
        middlewares = [ "homeassistant-allowlist" ];
      };

      services.homeassistant.loadBalancer.servers = [
        { url = "http://host.containers.internal:8123"; }
      ];

      middlewares = optionalAttrs (allowlistIps != [ ]) {
        homeassistant-allowlist.ipAllowList.sourceRange = allowlistIps;
      };
    };

    systemd.services."podman-homeassistant".preStart = ''
      if [ ! -e ${cfg.configPath}/configuration.yaml ]; then
        install -m 0644 ${initialConfig} ${cfg.configPath}/configuration.yaml
        echo "[]" > ${cfg.configPath}/automations.yaml
        touch ${cfg.configPath}/scripts.yaml ${cfg.configPath}/scenes.yaml
      fi
    '';
  };
}
