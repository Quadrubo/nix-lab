{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.bentopdf;
in
{
  options.myServices.bentopdf = {
    enable = mkEnableOption "BentoPDF";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/alam00000/bentopdf-simple:2.8.4"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for BentoPDF.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };
  };

  config = mkIf cfg.enable {
    myServices.monitoring.endpoints = [
      {
        name = "BentoPDF";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    myServices.podman = {
      enable = true;
      networks = [
        { name = "bentopdf"; }
      ];
    };

    virtualisation.oci-containers.containers.bentopdf = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=traefik"
        "--network=bentopdf"
        "--health-cmd=wget -O - http://localhost:8080 || exit 1"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=3"
        "--health-start-period=20s"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.bentopdf.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.bentopdf.entrypoints" = "websecure";
          "traefik.http.routers.bentopdf.tls.certresolver" = "myresolver";
          "traefik.http.services.bentopdf.loadbalancer.server.port" = "8080";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.bentopdf-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.bentopdf.middlewares" = "bentopdf-allowlist@docker";
        };
    };

    systemd.services."podman-bentopdf".after = [ "podman-network-bentopdf-container-user.service" ];
    systemd.services."podman-bentopdf".requires = [ "podman-network-bentopdf-container-user.service" ];
  };
}
