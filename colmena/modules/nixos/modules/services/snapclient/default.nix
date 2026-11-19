{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.snapclient;
in
{
  options.myServices.snapclient = {
    enable = mkEnableOption "Snapcast client playing a snapserver stream on a local sound card";

    server = mkOption {
      type = types.str;
      description = "Hostname or IP address of the snapserver.";
      example = "192.168.10.10";
    };

    soundcard = mkOption {
      type = types.str;
      default = "default";
      description = "ALSA PCM device to play on (see `snapclient --list`).";
      example = "sysdefault:CARD=Headphones";
    };

    testClients = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra clients (host IDs) that play into nothing, to set up and test
        rooms in Snapweb/Home Assistant before their speakers exist.
      '';
      example = [ "kueche" ];
    };
  };

  config = mkIf cfg.enable {
    systemd.services =
      listToAttrs (
        imap1 (
          i: hostId:
          nameValuePair "snapclient-test-${hostId}" {
            description = "Snapcast test client ${hostId} (no audio output)";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            serviceConfig = {
              ExecStart = escapeShellArgs [
                (getExe' pkgs.snapcast "snapclient")
                "--logsink"
                "stdout"
                "--hostID"
                hostId
                # Separate instance next to the real client on this host
                "--instance"
                (toString (i + 1))
                "--player"
                "file:filename=null"
                "tcp://${cfg.server}:1704"
              ];
              Restart = "always";
              RestartSec = 5;
              DynamicUser = true;
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              PrivateDevices = true;
            };
          }
        ) cfg.testClients
      )
      // {
        snapclient = {
          description = "Snapcast client";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "sound.target"
          ];

          serviceConfig = {
            ExecStart = escapeShellArgs [
              (getExe' pkgs.snapcast "snapclient")
              "--logsink"
              "stdout"
              # The hostname as client ID, so Snapweb keeps the client when the MAC changes
              "--hostID"
              config.networking.hostName
              "--soundcard"
              cfg.soundcard
              "tcp://${cfg.server}:1704"
            ];
            Restart = "always";
            RestartSec = 5;

            DynamicUser = true;
            SupplementaryGroups = [ "audio" ];
            StateDirectory = "snapclient";
            Environment = [ "HOME=/var/lib/snapclient" ];

            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictNamespaces = true;
            # Allow realtime priority, since Snapcast syncs playback in the low ms range
            LimitRTPRIO = 50;
            LimitRTTIME = "infinity";
          };
        };
      };
  };
}
