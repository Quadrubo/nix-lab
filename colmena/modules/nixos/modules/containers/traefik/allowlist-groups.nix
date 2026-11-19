# IP groups for the Traefik allowlists, the default of
# myServices.traefik.allowlistGroups
{
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

  helen = [
    "192.168.50.13/32" # WG - Helen iPad
  ];

  publy = [
    "192.168.60.1/32" # WG - Publy (Gatus monitoring)
  ];
}
