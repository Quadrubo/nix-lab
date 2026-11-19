{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.myServices.cdPlayer;
in
{
  options.myServices.cdPlayer = {
    enable = mkEnableOption "an MPD based audio CD player streaming to a snapserver TCP source";

    package = mkOption {
      type = types.package;
      description = "musy-player package, which loads inserted discs into MPD.";
    };

    device = mkOption {
      type = types.str;
      default = "/dev/cdrom";
      description = "CD drive to play from.";
    };

    server = mkOption {
      type = types.str;
      description = "Hostname or IP address of the snapserver.";
      example = "192.168.10.10";
    };

    streamPort = mkOption {
      type = types.port;
      default = 4953;
      description = "Port of the snapserver TCP source (myServices.snapcast.tcpSources on the server).";
    };

    port = mkOption {
      type = types.port;
      default = 6600;
      description = "MPD control port (Home Assistant's MPD integration connects here).";
    };

    allowedHosts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Hosts allowed to connect to the MPD control port, which has no password.";
      example = [ "192.168.10.12" ];
    };
  };

  config = mkIf cfg.enable {
    services.mpd = {
      enable = true;
      openFirewall = false;
      settings = {
        bind_to_address = "any";
        inherit (cfg) port;

        # Send no data while paused or stopped, so the CD stream goes idle and
        # Automatisch falls back to Spotify
        audio_output = [
          {
            type = "pipe";
            name = "snapcast";
            format = "44100:16:2";
            # Volume control for Home Assistant, for every room playing the CD
            mixer_type = "software";
            # Small buffers, since MPD writes faster than real time and buffered
            # audio delays pause, seek and skip
            command = "${pkgs.util-linux}/bin/pipesz --set 4096 --stdin -- ${getExe pkgs.socat} -u STDIN TCP:${cfg.server}:${toString cfg.streamPort},keepalive,keepidle=10,keepintvl=5,keepcnt=3,sndbuf=16384";
          }
        ];
      };
    };

    # Read the drive
    users.users.${config.services.mpd.user}.extraGroups = [ "cdrom" ];

    # Name every CD drive /dev/cdrom, since the kernel numbers them srN in plug order
    # and systemd only links sr0
    services.udev.extraRules = ''
      SUBSYSTEM=="block", KERNEL=="sr[0-9]*", SYMLINK+="cdrom"
    '';

    myModules.firewall.allowedTCPPortsFrom = [
      {
        inherit (cfg) port;
        hosts = cfg.allowedHosts;
      }
    ];

    systemd.services.musy-player = {
      description = "Load inserted audio CDs into MPD";
      wantedBy = [ "multi-user.target" ];
      wants = [ "mpd.service" ];
      after = [ "mpd.service" ];

      serviceConfig = {
        ExecStart = escapeShellArgs [
          (getExe cfg.package)
          "run"
          "--device"
          cfg.device
          "--mpd-port"
          (toString cfg.port)
        ];
        Restart = "on-failure";
        RestartSec = 5;

        DynamicUser = true;
        SupplementaryGroups = [ "cdrom" ];
        DevicePolicy = "closed";
        # Allow every CD drive, since the drive can appear after the service started
        DeviceAllow = [ "block-sr r" ];
        # Netlink receives the udev events about the drive
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
      };
    };
  };
}
