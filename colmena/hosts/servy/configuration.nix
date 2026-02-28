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
    };

    actual-server.instances = {
      personal = {
        enable = true;

        domain = "actual.l.qudr.de";
      };

      family = {
        enable = true;

        domain = "actual-g.l.qudr.de";
      };
    };

    beszel = {
      enable = true;

      domain = "beszel.l.qudr.de";
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

    chartdb = {
      enable = true;

      domain = "chartdb.l.qudr.de";
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
    };

    freshrss = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "freshrss.l.qudr.de";
    };

    gitea = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "gitea.l.qudr.de";
    };

    hedgedoc = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "hedgedoc.r.qudr.de";
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
    };

    paperless-ngx.instances = {
      family = {
        enable = true;
        sopsFile = ../../secrets/servy.yaml;

        domain = "paperless.l.qudr.de";
        appTitle = "Paperless (Gemeinsam)";

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
    };

    unifi-network-application = {
      enable = true;
      sopsFile = ../../secrets/servy.yaml;

      domain = "unifi.l.qudr.de";
    };
  };

  myModules.maintenance.enable = true;
}
