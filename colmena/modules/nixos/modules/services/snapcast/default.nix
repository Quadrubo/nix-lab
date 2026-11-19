{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.snapcast;

  allowlistIps = concatMap (g: config.myServices.traefik.allowlistGroups.${g}) cfg.allowlistGroups;

  tcpPipe = name: "${cfg.pipeDirectory}/tcp-${name}";

  tcpStreams = map (
    src:
    "pipe://${tcpPipe src.name}?name=${escapeURL src.name}&mode=read&sampleformat=${src.sampleFormat}&idle_threshold=${toString src.idleThreshold}"
  ) cfg.tcpSources;

  metaStreams = mapAttrsToList (
    name: streams:
    "meta:///${
      concatMapStringsSep "/" escapeURL streams
    }?name=${escapeURL name}&sampleformat=${cfg.metaSampleFormat}"
  ) cfg.metaStreams;
in
{
  options.myServices.snapcast = {
    enable = mkEnableOption "Snapcast server for synchronous multiroom audio";

    tcpSources = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Stream name shown in Snapweb.";
            };

            port = mkOption {
              type = types.port;
              description = "Port to listen on for this source's raw PCM.";
            };

            allowedHosts = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Hosts allowed to send to this source.";
            };

            sampleFormat = mkOption {
              type = types.str;
              default = "44100:16:2";
              description = "Format of the incoming PCM as <rate>:<bits>:<channels>.";
            };

            idleThreshold = mkOption {
              type = types.ints.positive;
              default = 1000;
              description = "Milliseconds without data before snapserver marks the stream idle.";
            };
          };
        }
      );
      default = [ ];
      description = "Streams that other hosts send over TCP, in the order snapserver lists them.";
      example = [
        {
          name = "CD";
          port = 4953;
        }
      ];
    };

    metaStreams = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = "Streams that play the first active one of the listed streams, keyed by stream name.";
      example = {
        Automatisch = [
          "CD"
          "Spotify"
        ];
      };
    };

    streaming.allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Snapclients allowed to connect to the audio stream (port 1704).";
    };

    control.allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Hosts allowed to use the JSON-RPC control API (port 1705), e.g. Home Assistant.";
    };

    domain = mkOption {
      type = types.str;
      description = "Domain for Snapweb, routed through Traefik.";
    };

    allowlistGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of Traefik IP group names to concatenate into an ipAllowList middleware. Groups are defined in myServices.traefik.allowlistGroups.";
    };

    defaultStream = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Stream that new clients start on, the first one if null.";
    };

    buffer = mkOption {
      type = types.ints.positive;
      default = 1000;
      description = "Latency in ms that clients buffer to play in sync.";
    };

    metaSampleFormat = mkOption {
      type = types.str;
      default = "44100:16:2";
      description = "Format of the meta streams, matching their sources.";
    };

    pipeDirectory = mkOption {
      type = types.str;
      default = "/run/snapcast";
      description = "Directory holding the named pipes that feed audio into snapserver.";
    };

    group = mkOption {
      type = types.str;
      default = "snapcast";
      description = "Group of snapserver and the relays to access the named pipes.";
    };
  };

  config = mkIf cfg.enable {
    myModules.firewall.allowedTCPPortsFrom = [
      {
        port = 1704;
        hosts = cfg.streaming.allowedHosts;
      }
      {
        port = 1705;
        hosts = cfg.control.allowedHosts;
      }
    ]
    ++ map (src: {
      inherit (src) port;
      hosts = src.allowedHosts;
    }) cfg.tcpSources;

    myServices.monitoring.endpoints = [
      {
        name = "Snapweb";
        group = "Servy - Internal";
        url = "https://${cfg.domain}";
      }
    ];

    # Snapweb listens on the host, which Traefik reaches through host.containers.internal
    myServices.traefik.dynamicHttp = {
      routers.snapweb = {
        rule = "Host(`${cfg.domain}`)";
        entryPoints = [ "websecure" ];
        tls.certResolver = "myresolver";
        service = "snapweb";
      }
      // optionalAttrs (allowlistIps != [ ]) {
        middlewares = [ "snapweb-allowlist" ];
      };

      services.snapweb.loadBalancer.servers = [
        { url = "http://host.containers.internal:1780"; }
      ];

      middlewares = optionalAttrs (allowlistIps != [ ]) {
        snapweb-allowlist.ipAllowList.sourceRange = allowlistIps;
      };
    };

    # Relay through socat, since snapserver's tcp:// source blocks after a sender vanishes
    systemd.services =
      listToAttrs (
        map (
          src:
          nameValuePair "snapcast-tcp-${src.name}" {
            description = "Relay TCP audio into the Snapcast ${src.name} stream";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network.target"
              "snapserver.service"
            ];
            bindsTo = [ "snapserver.service" ];

            serviceConfig = {
              ExecStart = escapeShellArgs [
                "${pkgs.util-linux}/bin/pipesz"
                "--set"
                "4096"
                "--stdout"
                "--"
                (getExe pkgs.socat)
                "-u"
                # Small buffer, every buffered second still plays after a pause on the sender
                "TCP-LISTEN:${toString src.port},reuseaddr,fork,keepalive,keepidle=10,keepintvl=5,keepcnt=3,rcvbuf=16384"
                "STDOUT"
              ];
              # Keep the pipe open across connections, so snapserver never sees an end of stream
              StandardOutput = "file:${tcpPipe src.name}";
              Restart = "always";
              RestartSec = 5;

              DynamicUser = true;
              SupplementaryGroups = [ cfg.group ];
              ReadWritePaths = [ cfg.pipeDirectory ];

              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              PrivateDevices = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
              RestrictNamespaces = true;
            };
          }
        ) cfg.tcpSources
      )
      // {
        snapserver = {
          after = [ "systemd-tmpfiles-setup.service" ];
          serviceConfig.SupplementaryGroups = [ cfg.group ];
        };
      };

    users.groups.${cfg.group} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.pipeDirectory} 0770 root ${cfg.group} -"
    ]
    ++ map (src: "p ${tcpPipe src.name} 0660 root ${cfg.group} -") cfg.tcpSources;

    services.snapserver = {
      enable = true;
      openFirewall = false;

      settings = {
        stream = {
          # Meta streams last, they reference the other streams by name
          source = tcpStreams ++ metaStreams;
          inherit (cfg) buffer;
        }
        // optionalAttrs (cfg.defaultStream != null) {
          default_source = cfg.defaultStream;
        };

        tcp-control.enabled = true;
        http.enabled = true;
      };
    };
  };
}
