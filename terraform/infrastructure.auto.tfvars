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
