{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.paperless-ngx;
  containerUserUid = 1000;
  containerUserGid = 100;
  paperlessUsermapUid = 0;
  paperlessUsermapGid = 0;

  instanceOptions = { name, ... }: {
    options = {
      enable = mkEnableOption "Enable this Paperless-ngx instance.";

      sopsFile = mkOption {
        type = types.path;
        description = "Path to sops file containing secrets.";
      };

      domain = mkOption {
        type = types.str;
        description = "Domain used for Paperless-ngx.";
      };

      appImage = mkOption {
        type = types.str;
        default = "ghcr.io/paperless-ngx/paperless-ngx:2.20.5"; # renovate: docker
      };

      dbImage = mkOption {
        type = types.str;
        default = "postgres:16-alpine"; # renovate: docker
      };

      redisImage = mkOption {
        type = types.str;
        default = "redis:8"; # renovate: docker
      };

      scanImage = mkOption {
        type = types.str;
        default = "manuc66/node-hp-scan-to:latest"; # renovate: docker
      };

      appTitle = mkOption {
        type = types.str;
        default = "Paperless";
        description = "Display title for Paperless-ngx.";
      };

      dataPath = mkOption {
        type = types.str;
        default = "/mnt/storage/containers/paperless-ngx-${name}/data";
        description = "Path to store Paperless data.";
      };

      mediaPath = mkOption {
        type = types.str;
        default = "/mnt/storage/containers/paperless-ngx-${name}/media";
        description = "Path to store Paperless media.";
      };

      consumePath = mkOption {
        type = types.str;
        default = "/mnt/storage/containers/paperless-ngx-${name}/consume";
        description = "Path to store Paperless consume directory.";
      };

      exportPath = mkOption {
        type = types.str;
        default = "/mnt/storage/containers/paperless-ngx-${name}/export";
        description = "Path to store Paperless export directory.";
      };

      dbDataPath = mkOption {
        type = types.str;
        default = "/mnt/storage/containers/paperless-ngx-${name}-db/data";
        description = "Path to store Postgres data.";
      };

      redisDataPath = mkOption {
        type = types.str;
        default = "/mnt/storage/containers/paperless-ngx-${name}-redis/data";
        description = "Path to store Redis data.";
      };

      scanTo = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable node-hp-scan-to container.";
        };

        ip = mkOption {
          type = types.str;
          description = "Scanner IP address.";
        };

        label = mkOption {
          type = types.str;
          description = "Scanner label.";
        };

        pattern = mkOption {
          type = types.str;
          default = "\"scan\"_dd.mm.yyyy_hh:MM:ss";
          description = "Scan file name pattern.";
        };
      };

      gpg = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable GPG decryption support.";
        };

        homePath = mkOption {
          type = types.str;
          default = "/mnt/storage/containers/paperless-ngx-${name}/gpg";
          description = "Path to the GPG home directory on the host.";
        };

        gpgConfText = mkOption {
          type = types.str;
          default = "pinentry-mode loopback\n";
          description = "Contents for gpg.conf in the GPG home.";
        };

        gpgAgentConfText = mkOption {
          type = types.str;
          default = "allow-loopback-pinentry\n";
          description = "Contents for gpg-agent.conf in the GPG home.";
        };
      };
    };
  };

  enabledInstances = filterAttrs (n: v: v.enable) cfg.instances;

  mkContainerPrefix = name: "paperless-ngx-${name}";

  mkInstanceContainers = name: instanceCfg:
    let
      prefix = mkContainerPrefix name;
      gpgHome = instanceCfg.gpg.homePath;
      gpgSocket = "${gpgHome}/S.gpg-agent";
      appSocketMounts = optionals instanceCfg.gpg.enable [
        "${gpgSocket}:/usr/src/paperless/.gnupg/S.gpg-agent"
      ];
    in
    {
      "${prefix}-redis" = {
        image = instanceCfg.redisImage;
        autoStart = true;

        podman.user = "container-user";

        extraOptions = [
          "--network=${prefix}"
        ];

        volumes = [
          "${instanceCfg.redisDataPath}:/data"
        ];
      };

      "${prefix}-db" = {
        image = instanceCfg.dbImage;
        autoStart = true;

        podman.user = "container-user";

        extraOptions = [
          "--network=${prefix}"
        ];

        environment = {
          POSTGRES_DB = "paperless";
          POSTGRES_USER = "paperless";
        };

        environmentFiles = [
          config.sops.secrets."${prefix}-db_env".path
        ];

        volumes = [
          "${instanceCfg.dbDataPath}:/var/lib/postgresql/data"
        ];
      };

      "${prefix}" = {
        image = instanceCfg.appImage;
        autoStart = true;

        podman.user = "container-user";

        extraOptions = [
          "--network=traefik"
          "--network=${prefix}"
        ];

        environment = {
          PAPERLESS_REDIS = "redis://${prefix}-redis:6379";
          PAPERLESS_DBHOST = "${prefix}-db";
          PAPERLESS_DBPORT = "5432";
          PAPERLESS_DBNAME = "paperless";
          PAPERLESS_DBUSER = "paperless";
          PAPERLESS_OCR_LANGUAGE = "deu+eng";
          PAPERLESS_URL = "https://${instanceCfg.domain}";
          USERMAP_UID = toString paperlessUsermapUid;
          USERMAP_GID = toString paperlessUsermapGid;
          PAPERLESS_APP_TITLE = instanceCfg.appTitle;
          PAPERLESS_CONSUMER_ENABLE_BARCODES = "true";
          PAPERLESS_CONSUMER_ENABLE_ASN_BARCODE = "true";
          PAPERLESS_CONSUMER_BARCODE_SCANNER = "ZXING";
        }
        // optionalAttrs instanceCfg.gpg.enable {
          PAPERLESS_ENABLE_GPG_DECRYPTOR = "true";
          PAPERLESS_EMAIL_GNUPG_HOME = "/usr/src/paperless/.gnupg";
          GNUPGHOME = "/usr/src/paperless/.gnupg";
        };

        environmentFiles = [
          config.sops.secrets."${prefix}_env".path
        ];

        volumes = [
          "${instanceCfg.dataPath}:/usr/src/paperless/data"
          "${instanceCfg.mediaPath}:/usr/src/paperless/media"
          "${instanceCfg.consumePath}:/usr/src/paperless/consume"
          "${instanceCfg.exportPath}:/usr/src/paperless/export"
        ]
        ++ optionals instanceCfg.gpg.enable [
          "${gpgHome}:/usr/src/paperless/.gnupg"
        ]
        ++ appSocketMounts;

        dependsOn = [
          "${prefix}-db"
          "${prefix}-redis"
        ];

        # TODO: migrate Traefik ip allowlist/denylist handling when ready.
        # Previously used labels (do not enable yet):
        # "traefik.http.middlewares.${prefix}-ipallowlist.ipallowlist.sourcerange" = "<comma-separated-ips>";
        # "traefik.http.routers.${prefix}.middlewares" = "${prefix}-ipallowlist@docker";
        labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.${prefix}.rule" = "Host(`${instanceCfg.domain}`)";
          "traefik.http.routers.${prefix}.entrypoints" = "websecure";
          "traefik.http.routers.${prefix}.tls.certresolver" = "myresolver";
        };
      };
    }
    // optionalAttrs instanceCfg.scanTo.enable {
      "${prefix}-node-hp-scan-to" = {
        image = instanceCfg.scanImage;
        autoStart = true;

        podman.user = "container-user";

        environment = {
          IP = instanceCfg.scanTo.ip;
          LABEL = instanceCfg.scanTo.label;
          DIR = "/scan";
          PATTERN = instanceCfg.scanTo.pattern;
          PUID = toString containerUserUid;
          PGID = toString containerUserGid;
          TZ = "Europe/Berlin";
        };

        volumes = [
          "${instanceCfg.consumePath}:/scan"
        ];
      };
    };

  mkSecrets = name: instanceCfg:
    let
      prefix = mkContainerPrefix name;
      gpgSecrets = optionalAttrs instanceCfg.gpg.enable {
        "${prefix}-gpg_fingerprint" = {
          sopsFile = instanceCfg.sopsFile;
          format = "yaml";
          key = "${prefix}-gpg_fingerprint";
          owner = "container-user";
        };
        "${prefix}-gpg_mail" = {
          sopsFile = instanceCfg.sopsFile;
          format = "yaml";
          key = "${prefix}-gpg_mail";
          owner = "container-user";
        };
        "${prefix}-gpg_private_key" = {
          sopsFile = instanceCfg.sopsFile;
          format = "yaml";
          key = "${prefix}-gpg_private_key";
          owner = "container-user";
        };
        "${prefix}-gpg_passphrase" = {
          sopsFile = instanceCfg.sopsFile;
          format = "yaml";
          key = "${prefix}-gpg_passphrase";
          owner = "container-user";
        };
      };
    in
    {
      "${prefix}_env" = {
        sopsFile = instanceCfg.sopsFile;
        format = "yaml";
        key = "${prefix}_env";
        owner = "container-user";
        restartUnits = [ "podman-${prefix}.service" ];
      };
      "${prefix}-db_env" = {
        sopsFile = instanceCfg.sopsFile;
        format = "yaml";
        key = "${prefix}-db_env";
        owner = "container-user";
        restartUnits = [ "podman-${prefix}-db.service" ];
      };
    } // gpgSecrets;

  mkTmpfiles = name: instanceCfg: [
    "d ${instanceCfg.consumePath} 0755 container-user users -"
    "d ${instanceCfg.dataPath} 0755 container-user users -"
    "d ${instanceCfg.exportPath} 0755 container-user users -"
    "d ${instanceCfg.mediaPath} 0755 container-user users -"
    "d ${instanceCfg.redisDataPath} 0755 container-user users -"
    "d ${instanceCfg.dbDataPath} 0755 container-user users -"
  ] ++ optionals instanceCfg.gpg.enable [
    "d ${instanceCfg.gpg.homePath} 0700 container-user users -"
  ];

  mkServiceDeps = name: instanceCfg:
    let
      prefix = mkContainerPrefix name;
      base = {
        "podman-${prefix}-db" = {
          after = [ "podman-network-${prefix}-container-user.service" ];
          requires = [ "podman-network-${prefix}-container-user.service" ];
        };
        "podman-${prefix}-redis" = {
          after = [ "podman-network-${prefix}-container-user.service" ];
          requires = [ "podman-network-${prefix}-container-user.service" ];
        };
        "podman-${prefix}" = {
          after = [
            "podman-network-${prefix}-container-user.service"
            "podman-network-traefik-container-user.service"
            "podman-${prefix}-db.service"
            "podman-${prefix}-redis.service"
          ]
          ++ optionals instanceCfg.gpg.enable [
            "paperless-ngx-${name}-gpg-setup.service"
            "paperless-ngx-${name}-gpg-cache.service"
          ];
          requires = [
            "podman-network-${prefix}-container-user.service"
            "podman-network-traefik-container-user.service"
            "podman-${prefix}-db.service"
            "podman-${prefix}-redis.service"
          ]
          ++ optionals instanceCfg.gpg.enable [
            "paperless-ngx-${name}-gpg-setup.service"
            "paperless-ngx-${name}-gpg-cache.service"
          ];
        };
      };
      gpgSetup = optionalAttrs instanceCfg.gpg.enable {
        "paperless-ngx-${name}-gpg-setup" = {
          description = "Paperless-ngx GPG setup for ${name}";
          serviceConfig = {
            Type = "oneshot";
            User = "container-user";
            Group = "users";
            RemainAfterExit = true;
          };
          path = [ pkgs.gnupg pkgs.coreutils ];
          script = let
            fingerprintFile = config.sops.secrets."${prefix}-gpg_fingerprint".path;
            keyFile = config.sops.secrets."${prefix}-gpg_private_key".path;
            gpgHome = instanceCfg.gpg.homePath;
            gpgSocket = "${instanceCfg.gpg.homePath}/S.gpg-agent";
          in ''
            set -euo pipefail
            export GNUPGHOME="${gpgHome}"
            touch "$GNUPGHOME/gpg.conf" "$GNUPGHOME/gpg-agent.conf"
            chmod 600 "$GNUPGHOME/gpg.conf" "$GNUPGHOME/gpg-agent.conf"
            cat > "$GNUPGHOME/gpg.conf" <<'EOF'
${instanceCfg.gpg.gpgConfText}
EOF
            if ! grep -q "^pinentry-mode " "$GNUPGHOME/gpg.conf"; then
              printf '%s\n' "pinentry-mode loopback" >> "$GNUPGHOME/gpg.conf"
            fi
            cat > "$GNUPGHOME/gpg-agent.conf" <<'EOF'
${instanceCfg.gpg.gpgAgentConfText}
EOF

            gpgconf --homedir "$GNUPGHOME" --kill gpg-agent || true
            gpgconf --homedir "$GNUPGHOME" --launch gpg-agent
            gpg-connect-agent --homedir "$GNUPGHOME" /bye

            agent_socket=$(gpgconf --homedir "$GNUPGHOME" --list-dirs agent-socket)
            if [ ! -S "$agent_socket" ]; then
              echo "GPG agent socket not found at $agent_socket" >&2
              exit 1
            fi
            ln -sf "$agent_socket" "$GNUPGHOME/S.gpg-agent"

            fingerprint=$(cat "${fingerprintFile}")
            if ! gpg --batch --list-secret-keys "$fingerprint" >/dev/null 2>&1; then
              gpg --batch --import "${keyFile}"
            fi

            if [ ! -S "${gpgSocket}" ]; then
              echo "GPG agent socket not found at ${gpgSocket}" >&2
              exit 1
            fi
          '';
          wantedBy = [ "multi-user.target" ];
        };
      };
      gpgCache = optionalAttrs instanceCfg.gpg.enable {
        "paperless-ngx-${name}-gpg-cache" = {
          description = "Paperless-ngx GPG passphrase cache for ${name}";
          after = [ "paperless-ngx-${name}-gpg-setup.service" ];
          requires = [ "paperless-ngx-${name}-gpg-setup.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "container-user";
            Group = "users";
            RemainAfterExit = true;
          };
          path = [ pkgs.gnupg pkgs.coreutils ];
          script = let
            mailFile = config.sops.secrets."${prefix}-gpg_mail".path;
            passphraseFile = config.sops.secrets."${prefix}-gpg_passphrase".path;
            gpgHome = instanceCfg.gpg.homePath;
          in ''
            set -euo pipefail
            export GNUPGHOME="${gpgHome}"
            gpgconf --homedir "$GNUPGHOME" --kill gpg-agent || true
            gpgconf --homedir "$GNUPGHOME" --launch gpg-agent
            gpg-connect-agent --homedir "$GNUPGHOME" /bye
            mail=$(cat "${mailFile}")
            echo "cache warmup" | gpg --batch --no-tty --pinentry-mode loopback \
              --passphrase-file "${passphraseFile}" --local-user "$mail" --sign \
              --output /dev/null
          '';
          wantedBy = [ "multi-user.target" ];
        };
      };
      scan = optionalAttrs instanceCfg.scanTo.enable {
        "podman-${prefix}-node-hp-scan-to" = {
          after = [ "podman-${prefix}.service" ];
          requires = [ "podman-${prefix}.service" ];
        };
      };
    in
    base // gpgSetup // gpgCache // scan;

  containers = foldl' (
    acc: name:
    acc // (mkInstanceContainers name enabledInstances.${name})
  ) { } (attrNames enabledInstances);

  sopsSecrets = foldl' (
    acc: name:
    acc // (mkSecrets name enabledInstances.${name})
  ) { } (attrNames enabledInstances);

  tmpfiles = concatMap (
    name: mkTmpfiles name enabledInstances.${name}
  ) (attrNames enabledInstances);

  serviceDeps = foldl' (
    acc: name:
    acc // (mkServiceDeps name enabledInstances.${name})
  ) { } (attrNames enabledInstances);

  gpgTimers = foldl' (
    acc: name:
    let
      instanceCfg = enabledInstances.${name};
      timerName = "paperless-ngx-${name}-gpg-cache";
    in
    acc // optionalAttrs instanceCfg.gpg.enable {
      "${timerName}" = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "30m";
          Unit = "${timerName}.service";
        };
      };
    }
  ) { } (attrNames enabledInstances);

in
{
  options.myServices.paperless-ngx = {
    instances = mkOption {
      type = types.attrsOf (types.submodule instanceOptions);
      default = { };
      description = "Paperless-ngx instances to run.";
    };
  };

  config = mkIf (enabledInstances != { }) {
    environment.systemPackages = mkIf (any (instanceCfg: instanceCfg.gpg.enable) (attrValues enabledInstances)) [
      pkgs.gnupg
    ];
    myServices.podman = {
      enable = true;
      networks =
        let
          names = attrNames enabledInstances;
          baseNetworks = map (name: { name = mkContainerPrefix name; }) names;
        in
        baseNetworks ++ [ { name = "traefik"; } ];
    };

    sops.secrets = sopsSecrets;

    systemd.tmpfiles.rules = tmpfiles;

    virtualisation.oci-containers.containers = containers;

    systemd.services = serviceDeps;
    systemd.timers = gpgTimers;
  };
}
