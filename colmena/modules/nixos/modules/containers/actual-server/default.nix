{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.actual-server;

  instanceOptions =
    { name, ... }:
    {
      options = {
        enable = mkEnableOption "Enable this Actual Server instance.";

        image = mkOption {
          type = types.str;
          default = "ghcr.io/actualbudget/actual:26.2.1"; # renovate: docker
          description = "The docker image to run.";
        };

        domain = mkOption {
          type = types.str;
          description = "The domain.";
        };

        dataPath = mkOption {
          type = types.str;
          default = "/mnt/storage/containers/actual-server-${name}/data";
          description = "Path to store data in.";
        };
      };
    };

  enabledInstances = filterAttrs (n: v: v.enable) cfg.instances;
in
{
  options = {
    myServices.actual-server = {
      instances = mkOption {
        type = types.attrsOf (types.submodule instanceOptions);
        default = { };
        description = "Actual Server instances to run.";
      };
    };
  };

  config = mkIf (enabledInstances != { }) {
    myServices.podman = {
      enable = true;
      networks = map (name: { name = "actual-server-${name}"; }) (attrNames enabledInstances);
    };

    # Directories
    systemd.tmpfiles.rules = mapAttrsToList (
      name: instanceCfg: "d ${instanceCfg.dataPath} 0755 container-user users -"
    ) enabledInstances;

    # Containers
    virtualisation.oci-containers.containers = mapAttrs' (
      name: instanceCfg:
      nameValuePair "actual-server-${name}" {
        image = instanceCfg.image;
        autoStart = true;

        extraOptions = [
          "--health-cmd=node src/scripts/health-check.js"
          "--health-interval=1m0s"
          "--health-retries=3"
          "--health-start-period=20s"
          "--health-timeout=10s"
          "--network=actual-server-${name}"
          "--network=traefik"
        ];

        podman = {
          user = "container-user";
          sdnotify = "healthy";
        };

        volumes = [
          "${instanceCfg.dataPath}:/data"
        ];

        labels = {
          "traefik.enable" = "true";
          # TODO: get ipallowlist working
          # "traefik.http.middlewares.actual-server-${name}-ipallowlist.ipallowlist.sourcerange" =
          #   "{{ (traefik_julian_ips) | join(',') }}";
          # "traefik.http.routers.actual-server-${name}.middlewares" = "actual-server-${name}-ipallowlist@docker";
          "traefik.http.routers.actual-server-${name}.rule" = "Host(`${instanceCfg.domain}`)";
          "traefik.http.routers.actual-server-${name}.entrypoints" = "websecure";
          "traefik.http.routers.actual-server-${name}.tls.certresolver" = "myresolver";
        };
      }
    ) enabledInstances;

    # Services
    systemd.services = mapAttrs' (
      name: instanceCfg:
      nameValuePair "podman-actual-server-${name}" {
        after = [ "podman-network-actual-server-${name}-container-user.service" ];
        requires = [ "podman-network-actual-server-${name}-container-user.service" ];
      }
    ) enabledInstances;
  };
}
