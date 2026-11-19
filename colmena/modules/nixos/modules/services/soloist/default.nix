{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  ...
}:

with lib;

let
  cfg = config.myServices.soloist;

  pipeDirectory = "/run/soloist-pcm";
  pipe = "${pipeDirectory}/pcm";
  sinkName = "snapcast-soloist";
in
{
  # TODO: drop once services.soloist and pkgs.soloist are in the stable release
  imports = [ "${nixpkgs-unstable}/nixos/modules/services/audio/soloist.nix" ];

  options.myServices.soloist = {
    enable = mkEnableOption "Spotify Soloist (official headless Spotify Connect receiver) streaming to a snapserver TCP source";

    sopsFile = mkOption {
      type = types.path;
      description = "Path to sops file containing secrets.";
    };

    name = mkOption {
      type = types.str;
      description = "Device name shown in Spotify Connect.";
    };

    server = mkOption {
      type = types.str;
      description = "Hostname or IP address of the snapserver.";
      example = "192.168.10.10";
    };

    websocket = {
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Enable Soloist's local WebSocket API (playback state and control) on this port.";
        example = 4955;
      };

      allowedHosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Hosts allowed to connect to the WebSocket API, which has no authentication.";
        example = [ "192.168.10.12" ];
      };
    };

    discovery.allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Hosts allowed to send mDNS queries for Spotify Connect discovery, e.g. an mDNS repeater.";
      example = [ "192.168.10.1" ];
    };

    login.allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Hosts allowed to log in to the device from the Spotify app.";
      example = [ "192.168.20.0/24" ];
    };

    port = mkOption {
      type = types.port;
      default = 4954;
      description = "Port of the snapserver TCP source (myServices.snapcast.tcpSources on the server).";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate = pkg: getName pkg == "soloist";

    sops.secrets."soloist_api_key" = {
      sopsFile = cfg.sopsFile;
      format = "yaml";
      key = "soloist_api_key";
      restartUnits = [ "soloist.service" ];
    };

    services.soloist = {
      enable = true;
      # Patch Spotify's binary with stable libraries, so it uses the same
      # PipeWire as the system-wide daemon instead of a second unstable closure
      package = pkgs.callPackage "${nixpkgs-unstable}/pkgs/by-name/so/soloist/package.nix" { };
      apiKeyFile = config.sops.secrets."soloist_api_key".path;
      deviceName = cfg.name;
      pipewireDevice = sinkName;
      websocketAddress = mkIf (cfg.websocket.port != null) "0.0.0.0:${toString cfg.websocket.port}";
    };

    myModules.firewall = {
      allowedTCPPortsFrom = optional (cfg.websocket.port != null) {
        inherit (cfg.websocket) port;
        hosts = cfg.websocket.allowedHosts;
      };

      allowedUDPPortsFrom = [
        {
          port = 5353;
          hosts = cfg.discovery.allowedHosts;
        }
      ];

      # Allow the whole ephemeral range, since Soloist binds its login port
      # randomly from it and that can't be configured
      allowedTCPPortRangesFrom = [
        {
          from = 32768;
          to = 60999;
          hosts = cfg.login.allowedHosts;
        }
      ];
    };

    # Link PipeWire's client.conf into /etc/pipewire, since Soloist only uses
    # PipeWire when that file exists and falls back to PulseAudio otherwise
    services.pipewire.configPackages = [
      (pkgs.runCommand "soloist-pipewire-client-conf" { } ''
        mkdir -p $out/share/pipewire
        ln -s ${config.services.pipewire.package}/share/pipewire/client.conf $out/share/pipewire/client.conf
      '')
    ];

    # Give Soloist a PipeWire to play to, since it can't output to ALSA or a
    # pipe itself. Its sink writes the raw PCM into a pipe for soloist-stream
    services.pipewire = {
      enable = true;
      systemWide = true;

      extraConfig.pipewire."90-snapcast-soloist"."context.modules" = [
        {
          name = "libpipewire-module-pipe-tunnel";
          args = {
            "tunnel.mode" = "sink";
            "pipe.filename" = pipe;
            "audio.format" = "S16LE";
            "audio.rate" = 44100;
            "audio.channels" = 2;
            "audio.position" = [
              "FL"
              "FR"
            ];
            "stream.props" = {
              "node.name" = sinkName;
              "node.description" = "Snapcast (${cfg.name})";
            };
          };
        }
      ];

      # Keep PipeWire off the sound cards, so snapclient can open them through
      # ALSA and Soloist's audio only goes to the pipe sink
      wireplumber.extraConfig."90-no-devices"."wireplumber.profiles".main = {
        "monitor.alsa" = "disabled";
        "monitor.bluez" = "disabled";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${pipeDirectory} 0750 pipewire pipewire -"
      "p ${pipe} 0640 pipewire pipewire -"
    ];

    systemd.services.soloist-stream = {
      description = "Send Soloist audio to snapserver";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
      ];

      serviceConfig = {
        ExecStart = escapeShellArgs [
          (getExe pkgs.socat)
          "-u"
          "OPEN:${pipe},rdonly"
          # Small send buffer, every buffered second still plays after a pause
          "TCP:${cfg.server}:${toString cfg.port},keepalive,keepidle=10,keepintvl=5,keepcnt=3,sndbuf=16384"
        ];
        Restart = "always";
        RestartSec = 5;

        DynamicUser = true;
        SupplementaryGroups = [ "pipewire" ];

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
    };
  };
}
