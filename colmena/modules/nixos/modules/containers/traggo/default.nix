{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.traggo;
in
{
  options.myServices.traggo = {
    enable = mkEnableOption "Traggo";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "traggo/server:0.8.3"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Traggo.";
    };

    dataPath = mkOption {
      type = types.str;
      default = "/mnt/storage/containers/traggo/data";
      description = "Path to store Traggo data.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware (e.g. [ \"julian\" \"lara\" ]). Groups are defined in myServices.traefik.allowlistGroups.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "traggo"; }
      ];
    };

    sops.secrets."traggo_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "traggo_env";
      owner = "container-user";
      restartUnits = [
        "podman-traggo.service"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataPath} 0755 container-user users -"
    ];

    virtualisation.oci-containers.containers.traggo = {
      image = cfg.image;
      autoStart = true;

      podman.user = "container-user";

      extraOptions = [
        "--network=traefik"
        "--network=traggo"
      ];

      environmentFiles = [ config.sops.secrets."traggo_env".path ];

      volumes = [
        "${cfg.dataPath}:/opt/traggo/data"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.traggo.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.traggo.entrypoints" = "websecure";
          "traefik.http.routers.traggo.tls.certresolver" = "myresolver";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.traggo-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.traggo.middlewares" = "traggo-allowlist@docker";
        };
    };

    systemd.services."podman-traggo".after = [ "podman-network-traggo-container-user.service" ];
    systemd.services."podman-traggo".requires = [ "podman-network-traggo-container-user.service" ];
  };
}
