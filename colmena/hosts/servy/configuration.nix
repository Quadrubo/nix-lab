{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
    ../../modules/nixos/default.nix
  ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  system.stateVersion = "25.11";

  nix.settings.trusted-users = [
    "root"
    "colmena"
  ];

  # General Settings
  users.users.colmena = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOIyANbVLEpwzS/2D5eNU40mOIuOOqTcJFUr3LY0+xt julian@nixos" # compy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOBhaJ29X++P+Ceu01qSdMeQcjviiG4rIL/GHJRorJ9 julian@nixos" # framy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5KNuNmb6r4l7wDsebVHvEbahtqTkssU8KB7t1u9bGY julian@nixos" # work
    ];
  };

  users.users.julian = {
    isNormalUser = true;
    uid = 1002;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOIyANbVLEpwzS/2D5eNU40mOIuOOqTcJFUr3LY0+xt julian@nixos" # compy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOBhaJ29X++P+Ceu01qSdMeQcjviiG4rIL/GHJRorJ9 julian@nixos" # framy
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5KNuNmb6r4l7wDsebVHvEbahtqTkssU8KB7t1u9bGY julian@nixos" # work
    ];
  };

  # Allow passwordless sudo for julian
  security.sudo.extraRules = [
    {
      users = [
        "julian"
        "colmena"
      ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  time.timeZone = "Europe/Berlin";

  networking.firewall.enable = true;
  networking.hostId = "ccb0cce0";
  console.keyMap = "de";

  # Sops
  sops.defaultSopsFile = ../../secrets/servy.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets.zfs_storage_pool_key = {
    sopsFile = ../../secrets/servy.yaml;
    format = "yaml";
    key = "zfs_storage_pool_key";
    owner = "root";
    group = "root";
    mode = "0400";
    path = "/run/secrets/zfs_storage_pool_key";
  };

  boot.zfs.forceImportRoot = true;
  boot.zfs.forceImportAll = true;
  boot.zfs.extraPools = [ "storage_pool" ];
  boot.supportedFilesystems = [ "zfs" ];

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };

  # TODO: find place for tmux
  # TODO: get nix-shell or nix shell working for debugging
  environment.systemPackages = with pkgs; [
    tmux
  ];

  sops.secrets."ghcr_token" = {
    format = "yaml";
    key = "ghcr_token";
    owner = "container-user";
  };

  # Containers
  myServices = {
    podman = {
      enable = true;

      ghcr = {
        enable = true;

        username = "Quadrubo";
        tokenFile = config.sops.secrets."ghcr_token".path;
      };
    };

    traefik = {
      enable = true;

      dnsChallenge = {
        enable = true;

        sopsFile = ../../secrets/home.yaml;
      };

      allowlistGroups = {
        servy = [
          "192.168.10.10/32" # DMZ - Servy
          "172.17.0.0/12" # Docker
          "192.168.0.0/16" # Docker
        ];

        julian = [
          "192.168.20.10/32" # USER - Framy
          "192.168.50.3/32" # WG   - Framy
          "192.168.20.11/32" # USER - Phony
          "192.168.50.2/32" # WG   - Phony
          "192.168.20.12/32" # USER - Compy
          "192.168.20.13/32" # USER - Worky
          "192.168.50.4/32" # WG   - Worky
        ];

        lara = [
          "192.168.20.20/32" # USER - Lara iPhone
          "192.168.50.5/32" # WG   - Lara iPhone
          "192.168.20.21/32" # USER - Lara iPad
          "192.168.50.6/32" # WG   - Lara iPad
          "192.168.20.22/32" # USER - Lara Laptop
          "192.168.50.7/32" # WG   - Lara Laptop
        ];

        fabi = [
          "192.168.50.10/32" # WG - Fabi PC
        ];

        papa = [
          "192.168.50.11/32" # WG - Papa Handy
        ];

        mama = [
          "192.168.50.12/32" # WG - Mama Handy
        ];

        chromecasts = [
          "192.168.30.11/32" # IOT - Dachgeschoss (Chromecast Wohnzimmer)
          "192.168.30.12/32" # IOT - Kaufhof (Chromecast Schlafzimmer)
        ];

        larac = [
          "192.168.50.8/32" # WG  - Lara C. iPhone
          "192.168.50.9/32" # WG  - Lara C. iPad
        ];
      };
    };

    actual-server.instances = {
      personal = {
        enable = true;

        domain = "actual.l.qudr.de";
        allowlistGroups = [ "julian" ];
      };

      family = {
        enable = true;

        domain = "actual-g.l.qudr.de";
        allowlistGroups = [
          "julian"
          "lara"
        ];
      };
    };

    beszel = {
      enable = true;

      domain = "beszel.l.qudr.de";
      allowlistGroups = [
        "servy"
        "julian"
      ];
    };

    beszel-agent = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP0vtzOrcit3+zUzMAQ80IK04Og+WJ0O3hMnaF4FLiG";
      hubUrl = "https://beszel.l.qudr.de";

      extraFilesystems = [
        {
          name = "zfs";
          path = "/mnt/storage";
        }
      ];

      devices = [
        "/dev/sda"
        "/dev/sdb"
        "/dev/sdc"
        "/dev/sdd"
        "/dev/nvme0n1"
        "/dev/nvme1n1"
      ];
    };

    bitwarden-backup = {
      enable = true;

      sopsFile = ../../secrets/servy.yaml;
    };

    borgmatic = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      # Daily at 1am
      cronSchedule = "0 1 * * *";

      sshCommand = "ssh -p 23 -i /root/.ssh/sub4";

      sourceDirectories = [
        "/mnt/storage/backups" # Backups from phone, etc.
        "/mnt/storage/containers"
        "/mnt/storage/documents"
      ];

      repositories = [
        {
          path = "ssh://u333539-sub4@u333539.your-storagebox.de/./backup";
          label = "Boxy";
        }
      ];

      mariadbDatabases = [
        {
          name = "gitea";
          hostname = "127.0.0.1";
          port = 3307;
          username = "gitea";
          password = "\${GITEA_DB_PASSWORD}";
          options = "--skip-ssl";
        }
        {
          name = "nextcloud";
          hostname = "127.0.0.1";
          port = 3308;
          username = "nextcloud";
          password = "\${NEXTCLOUD_DB_PASSWORD}";
          options = "--skip-ssl";
        }
        # TODO: pelican
        {
          name = "speedtest_tracker";
          hostname = "127.0.0.1";
          port = 3309;
          username = "speedtest";
          password = "\${SPEEDTEST_TRACKER_DB_PASSWORD}";
          options = "--skip-ssl";
        }
      ];

      networks = [
        { name = "borgmatic"; }
      ];
    };

    chartdb = {
      enable = true;

      domain = "chartdb.l.qudr.de";
      allowlistGroups = [ "julian" ];
    };

    crowdsec = {
      enable = true;

      parsers = [ "crowdsecurity/nextcloud-whitelist" ];
    };

    crowdsec-firewall-bouncer = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;
    };

    dawarich = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "dawarich.l.qudr.de";
      allowlistGroups = [ "julian" ];
    };

    freshrss = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "freshrss.l.qudr.de";
      allowlistGroups = [ "julian" ];
    };

    gitea = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "gitea.l.qudr.de";
      allowlistGroups = [ "julian" ];
      dbLocalhostPort = 3307;
    };

    hedgedoc = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "hedgedoc.r.qudr.de";
      allowlistGroups = [
        "julian"
        "lara"
      ];
    };

    hemmelig = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "hemmelig.r.qudr.de";
    };

    immich = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "immich.r.qudr.de";
    };

    kitchenowl = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "kitchenowl.r.qudr.de";
    };

    nextcloud = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "nextcloud.r.qudr.de";
      cspHostname = "qudr.de";
      dbLocalhostPort = 3308;
    };

    ntfy = {
      enable = true;

      domain = "ntfy.r.qudr.de";
    };

    obsidian-livesync = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "obsidian-livesync.r.qudr.de";
    };

    # TOOD: get this container working
    # maybe it can work without being exposed
    onlyoffice-documentserver = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "nextcloudds.r.qudr.de";
    };

    open-archiver = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "open-archiver.l.qudr.de";
      allowlistGroups = [ "julian" ];
    };

    paperless-ngx.instances = {
      family = {
        enable = true;
        sopsFile = ../../secrets/servy.yaml;

        domain = "paperless.l.qudr.de";
        appTitle = "Paperless (Gemeinsam)";
        allowlistGroups = [
          "julian"
          "lara"
        ];

        scanTo = {
          ip = "192.168.30.10";
          label = "Paperless-Gemeinsam";
        };

        gpg = {
          enable = true;
        };
      };

      julian = {
        enable = true;
        sopsFile = ../../secrets/servy.yaml;

        domain = "paperless-j.l.qudr.de";
        appTitle = "Paperless (Julian)";
        allowlistGroups = [ "julian" ];

        scanTo = {
          ip = "192.168.30.10";
          label = "Paperless-Julian";
        };

        gpg = {
          enable = true;
        };
      };

      lara = {
        enable = true;
        sopsFile = ../../secrets/servy.yaml;

        domain = "paperless-l.l.qudr.de";
        appTitle = "Paperless (Lara)";
        allowlistGroups = [ "lara" ];

        scanTo = {
          ip = "192.168.30.10";
          label = "Paperless-Lara";
        };
      };
    };

    # TODO: get this working on rootless podman
    pelican = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      panelDomain = "pelican-panel.l.qudr.de";
      wingsDomain = "pelican-wings.l.qudr.de";
    };

    # TODO: remove, beszel replaces it
    scrutiny = {
      enable = false;

      domain = "scrutiny.l.qudr.de";

      devices = [
        "/dev/sda"
        "/dev/sdb"
        "/dev/sdc"
        "/dev/sdd"
        "/dev/nvme0n1"
        "/dev/nvme1n1"
      ];
    };

    speedtest-tracker = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "speedtest.l.qudr.de";
      allowlistGroups = [ "julian" ];
      dbLocalhostPort = 3309;
    };

    spliit = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "spliit.r.qudr.de";
    };

    syncthing = {
      enable = true;

      domain = "syncthing.r.qudr.de";
    };

    traggo = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "traggo.l.qudr.de";
      allowlistGroups = [ "julian" ];
    };

    unifi-network-application = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "unifi.l.qudr.de";
      allowlistGroups = [ "julian" ];
    };
  };

  myModules.maintenance.enable = true;
}
