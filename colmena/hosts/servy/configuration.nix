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

  boot.loader.grub.enable = true;

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

  # Sops
  sops.defaultSopsFile = ../../secrets/servy.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

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
        enable = false;

        domain = "actual.l.mailward.de";
      };

      family = {
        enable = false;

        domain = "actual-g.l.mailward.de";
      };
    };

    beszel = {
      enable = false;

      domain = "beszel.l.mailward.de";
    };

    beszel-agent = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP0vtzOrcit3+zUzMAQ80IK04Og+WJ0O3hMnaF4FLiG";
      hubUrl = "https://beszel.l.qudr.de";
    };

    bitwarden-backup = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;
    };

    chartdb = {
      enable = false;

      domain = "chartdb.l.mailward.de";
    };

    crowdsec = {
      enable = false;

      parsers = [ "crowdsecurity/nextcloud-whitelist" ];
    };

    crowdsec-firewall-bouncer = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;
    };

    dawarich = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "dawarich.l.mailward.de";
    };

    freshrss = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "freshrss.l.mailward.de";
    };

    gitea = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "gitea.l.mailward.de";
    };

    hedgedoc = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "hedgedoc.r.mailward.de";
    };

    hemmelig = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "hemmelig.r.mailward.de";
    };

    immich = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "immich.r.mailward.de";

      # TODO: remove options when on actual hardware
      enableMachineLearning = false;
    };

    kitchenowl = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "kitchenowl.r.mailward.de";
    };

    nextcloud = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "nextcloud.r.mailward.de";
      cspHostname = "mailward.de";
    };

    ntfy = {
      enable = false;

      domain = "ntfy.r.mailward.de";
    };

    obsidian-livesync = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "obsidian-livesync.r.mailward.de";
    };

    onlyoffice-documentserver = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "nextcloudds.r.mailward.de";
    };

    open-archiver = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "open-archiver.l.mailward.de";
    };

    paperless-ngx.instances = {
      family = {
        enable = false;
        sopsFile = ../../secrets/servy.yaml;

        domain = "paperless.l.mailward.de";
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
        enable = false;
        sopsFile = ../../secrets/servy.yaml;

        domain = "paperless-j.l.mailward.de";
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
        enable = false;
        sopsFile = ../../secrets/servy.yaml;

        domain = "paperless-l.l.mailward.de";
        appTitle = "Paperless (Lara)";

        scanTo = {
          ip = "192.168.30.10";
          label = "Paperless-Lara";
        };
      };
    };

    pelican = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      panelDomain = "pelican-panel.l.mailward.de";
      wingsDomain = "pelican-wings.l.mailward.de";
    };

    scrutiny = {
      enable = false;

      domain = "scrutiny.l.mailward.de";

      # TODO: add these options on actual hardware
      # devices = [
      #   "/dev/sda"
      #   "/dev/sdb"
      #   "/dev/sdc"
      #   "/dev/sdd"
      #   "/dev/nvme0n1"
      #   "/dev/nvme1n1"
      # ];
    };

    speedtest-tracker = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "speedtest.l.mailward.de";
    };

    spliit = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "spliit.r.mailward.de";
    };

    syncthing = {
      enable = false;

      domain = "syncthing.r.mailward.de";
    };

    traggo = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "traggo.l.mailward.de";
    };

    unifi-network-application = {
      enable = false;
      sopsFile = ../../secrets/servy.yaml;

      domain = "unifi.l.mailward.de";
    };
  };

  myModules.maintenance.enable = true;
}
