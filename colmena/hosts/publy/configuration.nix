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

  nix.settings = {
    trusted-users = [
      "root"
      "colmena"
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

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

  # Sops
  sops.defaultSopsFile = ../../secrets/publy.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets."ghcr_token" = {
    format = "yaml";
    key = "ghcr_token";
    owner = "container-user";
  };

  # Programs
  myServices.fail2ban.enable = true;

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

    beszel-agent = {
      enable = true;
      sopsFile = ../../secrets/publy.yaml;

      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPP0vtzOrcit3+zUzMAQ80IK04Og+WJ0O3hMnaF4FLiG";
      hubUrl = "https://beszel.l.qudr.de";
    };

    traefik.enable = true;

    gatus = {
      enable = true;
      sopsFile = ../../secrets/publy.yaml;

      domain = "gatus.r.qudr.de";
      dns = "192.168.10.11";
      hostOverrides = [
        "gatus.r.qudr.de"
        "julweb.dev"
        "analytics.julweb.dev"
        "ntfy.r.qudr.de"
      ];

      alerting.ntfy = {
        enable = true;
        url = "https://ntfy.r.qudr.de";
        topic = "gatus";
      };
    };

    julweb = {
      enable = true;
      sopsFile = ../../secrets/publy.yaml;
      dbLocalhostPort = 3306;
    };

    umami = {
      enable = true;
      sopsFile = ../../secrets/publy.yaml;
      dbLocalhostPort = 5432;
    };

    ntfy = {
      enable = true;

      domain = "ntfy.r.qudr.de";
    };

    borgmatic = {
      enable = true;
      sopsFile = ../../secrets/publy.yaml;

      # Daily at 2am
      cronSchedule = "0 2 * * *";

      sshCommand = "ssh -p 23 -i /root/.ssh/sub1";

      sourceDirectories = [
        "/mnt/storage/containers"
      ];

      repositories = [
        {
          path = "ssh://u333539-sub1@u333539.your-storagebox.de/./backup";
          label = "Boxy";
        }
      ];

      mariadbDatabases = [
        {
          name = "julweb";
          hostname = "127.0.0.1";
          port = 3306;
          username = "julweb";
          password = "\${JULWEB_DB_PASSWORD}";
          options = "--skip-ssl";
        }
      ];

      postgresqlDatabases = [
        {
          name = "umami";
          hostname = "127.0.0.1";
          port = 5432;
          username = "umami";
          password = "\${UMAMI_DB_PASSWORD}";
        }
      ];

      networks = [
        { name = "borgmatic"; }
      ];
    };

    wireguard = {
      enable = true;
      sopsFile = ../../secrets/publy.yaml;

      # Server - listens for incoming connections from home servers
      address = "192.168.60.1/24";
      listenPort = 51820;

      peers = [
        {
          # servy
          publicKey = "caUJug8M+5300cNyg/4Tk6gWXLd6xcHV/449RAPO0XM=";
          allowedIPs = [
            "192.168.60.0/24"
            "192.168.10.0/24"
          ];
        }
      ];
    };

    crowdsec.enable = true;
    crowdsec-firewall-bouncer = {
      enable = true;
      sopsFile = ../../secrets/publy.yaml;
    };
  };

  myModules.maintenance.enable = true;
}
