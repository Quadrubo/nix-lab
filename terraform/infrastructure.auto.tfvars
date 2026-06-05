servers = {
  # "servy" = {
  #   server_type = "cx23"
  #   private_ip  = "10.0.1.3"
  # }
}

storage_boxes = {
  "Boxy" = {
    location         = "fsn1"
    storage_box_type = "bx11"
  }
}

storage_box_subaccounts = {
  "sub1" = {
    storage_box_id = "Boxy"
    home_directory = "publy"
    description    = "borgmatic (Publy)"
  }
  "sub2" = {
    storage_box_id = "Boxy"
    home_directory = "raspy"
    description    = "borgmatic (Raspy)"
  }
  "sub3" = {
    storage_box_id = "Boxy"
    home_directory = "andrea"
    description    = "borgmatic (Andrea)"
  }
  "sub4" = {
    storage_box_id = "Boxy"
    home_directory = "servy"
    description    = "borgmatic (Servy)"
  }
}

admin_keys = {
  framy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOBhaJ29X++P+Ceu01qSdMeQcjviiG4rIL/GHJRorJ9 julian@nixos"
  compy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOIyANbVLEpwzS/2D5eNU40mOIuOOqTcJFUr3LY0+xt julian@nixos"
  work  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN5KNuNmb6r4l7wDsebVHvEbahtqTkssU8KB7t1u9bGY julian@nixos"
}

domains = {
  "julweb.dev" = {
    zone_id = "35da8945ff73073ade7dc4bf61da4cfe"
    records = [
      {
        type    = "A"
        name    = "@"
        content = "202.61.254.52"
      },
      {
        type    = "A"
        name    = "www"
        content = "202.61.254.52"
      },
      {
        type    = "A"
        name    = "analytics"
        content = "202.61.254.52"
      },
      {
        type    = "A"
        name    = "node-exporter"
        content = "202.61.254.52"
      },
      {
        type    = "CNAME"
        name    = "mbo0001._domainkey"
        content = "mbo0001._domainkey.mailbox.org"
      },
      {
        type    = "CNAME"
        name    = "mbo0002._domainkey"
        content = "mbo0002._domainkey.mailbox.org"
      },
      {
        type    = "CNAME"
        name    = "mbo0003._domainkey"
        content = "mbo0003._domainkey.mailbox.org"
      },
      {
        type    = "CNAME"
        name    = "mbo0004._domainkey"
        content = "mbo0004._domainkey.mailbox.org"
      },
      {
        type     = "MX"
        name     = "julweb.dev"
        content  = "mxext1.mailbox.org"
        priority = 10
      },
      {
        type     = "MX"
        name     = "julweb.dev"
        content  = "mxext2.mailbox.org"
        priority = 10
      },
      {
        type     = "MX"
        name     = "julweb.dev"
        content  = "mxext3.mailbox.org"
        priority = 20
      },
      {
        type    = "TXT"
        name    = "3fb4d98a4e3cdac8ce0d090b0b507f3f3569a355"
        content = "\"42618499e0fc4ebf159286678c13ac1c5a3c1c86\""
      },
      {
        type    = "TXT"
        name    = "_dmarc"
        content = "\"v=DMARC1;p=none;rua=mailto:postmaster@julweb.dev\""
      },
      {
        type    = "TXT"
        name    = "julweb.dev"
        content = "\"v=spf1 include:mailbox.org ~all\""
      }
    ]
  }
  "qudr.de" = {
    zone_id = "15e6d82b11850b058742de244ddf92c9"
    records = [
      {
        type    = "A"
        name    = "gatus.r"
        content = "202.61.254.52"
      },
      {
        type    = "A"
        name    = "ntfy.r"
        content = "202.61.254.52"
      },
      {
        type = "CAA"
        name = "r"
        data = {
          flags = 0
          tag   = "issue"
          value = "letsencrypt.org"
        }
      },
      {
        type    = "CNAME"
        name    = "hedgedoc.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "hemmelig.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "immich.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "kitchenowl.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "mc-fabi.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "mc-julian.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "nextcloudds.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "nextcloud.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "obsidian-livesync.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "spliit.r"
        content = "ddns.qudr.de"
      },
      {
        type    = "CNAME"
        name    = "syncthing.r"
        content = "ddns.qudr.de"
      },
      {
        type     = "MX"
        name     = "qudr.de"
        content  = "mxext1.mailbox.org"
        priority = 10
      },
      {
        type     = "MX"
        name     = "qudr.de"
        content  = "mxext2.mailbox.org"
        priority = 10
      },
      {
        type     = "MX"
        name     = "qudr.de"
        content  = "mxext3.mailbox.org"
        priority = 20
      },
      {
        type    = "TXT"
        name    = "57ca78632807b82ca3dd399c68c331dd29dbd867"
        content = "5e5cdaff7ccc57073df938014ded5d7f3d51b65f"
      },
      {
        type    = "TXT"
        name    = "qudr.de"
        content = "\"v=spf1 include:mailbox.org ~all\""
      }
    ]
  }
  # "mailward.de" = {
  #   zone_id = "25eb49fa4d6f88565b27902a556e0979"
  #   records = [{
  #     type        = "A"
  #     name        = "*"
  #     server_name = "servy"
  #   }]
  # }
}
