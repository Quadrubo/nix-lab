{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.myServices.vaultwarden;
in
{
  options.myServices.vaultwarden = {
    enable = mkEnableOption "Vaultwarden";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    image = mkOption {
      type = types.str;
      default = "vaultwarden/server:1.35.7"; # renovate: docker
    };

    domain = mkOption {
      type = types.str;
      description = "Domain used for Vaultwarden.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };
  };

  config = mkIf cfg.enable {
    myServices.podman = {
      enable = true;
      networks = [
        { name = "vaultwarden"; }
      ];
    };

    sops.secrets."vaultwarden_env" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "vaultwarden_env";
      owner = "container-user";
      restartUnits = [
        "podman-vaultwarden.service"
      ];
    };

    # Directories
    systemd.tmpfiles.rules = [
      "d /mnt/storage/containers/vaultwarden 0755 container-user users -"
      "d /mnt/storage/containers/vaultwarden/data 0755 container-user users -"
    ];

    # App
    virtualisation.oci-containers.containers.vaultwarden = {
      image = cfg.image;
      autoStart = true;

      podman = {
        user = "container-user";
        sdnotify = "healthy";
      };

      extraOptions = [
        "--network=traefik"
        "--network=vaultwarden"
        "--health-cmd=curl -sf http://localhost:80/alive || exit 1"
        "--health-interval=30s"
        "--health-timeout=10s"
        "--health-retries=3"
        "--health-start-period=20s"
      ];

      environment = {
        DOMAIN = "https://${cfg.domain}";
        SIGNUPS_ALLOWED = "false";
        INVITATIONS_ALLOWED = "false";
        SHOW_PASSWORD_HINT = "false";
        PUSH_ENABLED = "true";
        PUSH_RELAY_URI = "https://api.bitwarden.eu";
        PUSH_IDENTITY_URI = "https://identity.bitwarden.eu";
      };

      environmentFiles = [ config.sops.secrets."vaultwarden_env".path ];

      volumes = [
        "/mnt/storage/containers/vaultwarden/data:/data"
      ];

      labels =
        let
          allowlistIps = lib.concatMap (
            g: config.myServices.traefik.allowlistGroups.${g}
          ) cfg.allowlistGroups;
        in
        {
          "traefik.enable" = "true";
          "traefik.http.routers.vaultwarden.rule" = "Host(`${cfg.domain}`)";
          "traefik.http.routers.vaultwarden.entrypoints" = "websecure";
          "traefik.http.routers.vaultwarden.tls.certresolver" = "myresolver";
          "traefik.http.services.vaultwarden.loadbalancer.server.port" = "80";
        }
        // lib.optionalAttrs (allowlistIps != [ ]) {
          "traefik.http.middlewares.vaultwarden-allowlist.ipallowlist.sourcerange" =
            lib.concatStringsSep "," allowlistIps;
          "traefik.http.routers.vaultwarden.middlewares" = "vaultwarden-allowlist@docker";
        };
    };

    systemd.services."podman-vaultwarden".after = [
      "podman-network-vaultwarden-container-user.service"
    ];
    systemd.services."podman-vaultwarden".requires = [
      "podman-network-vaultwarden-container-user.service"
    ];
  };
}
