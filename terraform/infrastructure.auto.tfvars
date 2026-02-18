servers = {
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
  #   framy = "ssh-ed25519 AAAA... user@framy"
  compy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOIyANbVLEpwzS/2D5eNU40mOIuOOqTcJFUr3LY0+xt julian@nixos"
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
}
