{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.podman;

  networkServices = listToAttrs (
    map (net: {
      name = "podman-network-${net.name}-${net.user}";
      value = {
        path = [
          pkgs.podman
          # required so podman can find the SUID newuidmap binary at boot
          "/run/wrappers"
        ];
        script = "podman network exists ${net.name} || podman network create ${net.name}";
        serviceConfig = {
          Type = "oneshot";
          User = net.user;
          RemainAfterExit = true;
        }
        // optionalAttrs (net.group != null) {
          Group = net.group;
        };
        wantedBy = [ "multi-user.target" ];
      };
    }) cfg.networks
  );

  loginService = optionalAttrs cfg.ghcr.enable {
    "podman-registry-login-ghcr" = {
      description = "Login to GHCR for Podman";
      after = [
        "network-online.target"
        "linger-users.service"
        "user@1000.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "user@1000.service" ];
      wantedBy = [ "multi-user.target" ];
      # required so podman can find the SUID newuidmap binary at boot
      path = [ "/run/wrappers" ];
      serviceConfig = {
        Type = "oneshot";
        User = "container-user";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "podman-ghcr-login" ''
          cat ${cfg.ghcr.tokenFile} | \
          ${pkgs.podman}/bin/podman login ghcr.io \
            --username ${cfg.ghcr.username} \
            --password-stdin
        '';
      };
    };
  };

in
{
  options.myServices.podman = {
    enable = mkEnableOption "Podman Helpers";

    networks = mkOption {
      type = types.listOf (
        types.submodule (
          { ... }:
          {
            options = {
              name = mkOption {
                type = types.str;
                description = "Podman network name.";
              };
              user = mkOption {
                type = types.str;
                default = "container-user";
                description = "User that owns the rootless network.";
              };
              group = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Group used for the network unit, if needed.";
              };
            };
          }
        )
      );
      default = [ ];
      description = "List of Podman networks to create automatically (per user).";
    };

    mariadbTcLogGuard = mkOption {
      type = types.package;
      internal = true;
      description = ''
        Helper for a MariaDB container's ExecStartPre. Takes the host path of
        the container's tc.log and moves it aside if its magic header is not
        the expected fe230574, which otherwise makes mariadbd refuse to start
        and leaves the unit restart-looping. The file only holds in-flight
        two-phase-commit transaction ids, so discarding a broken one is safe.
      '';
      default = pkgs.writeShellScript "mariadb-tc-log-guard" ''
        set -u
        tclog="$1"
        [ -f "$tclog" ] || exit 0
        magic=$(${pkgs.coreutils}/bin/od -An -N4 -tx1 "$tclog" | ${pkgs.coreutils}/bin/tr -d " \n")
        [ "$magic" = "fe230574" ] && exit 0
        bak="$tclog.bad-$(${pkgs.coreutils}/bin/date +%Y%m%dT%H%M%S)"
        echo "tc.log magic is '$magic', expected 'fe230574'; moving to $bak" >&2
        ${pkgs.coreutils}/bin/mv "$tclog" "$bak"
      '';
    };

    ghcr = {
      enable = mkEnableOption "Login to GHCR";
      username = mkOption {
        type = types.str;
        default = "Quadrubo";
      };
      tokenFile = mkOption {
        type = types.path;
        description = "Path to the secret file containing the GHCR token";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /mnt/storage/cache 0755 container-user users -"
    ];

    systemd.services = networkServices // loginService;
  };
}
