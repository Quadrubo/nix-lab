{
  # Only report network-online once a real DHCP lease exists. Otherwise dhcpcd
  # signals online with a link-local address before the lease arrives, and
  # services that need DNS at boot fail
  networking.dhcpcd.wait = "ipv4";
  networking.dhcpcd.extraConfig = "noipv4ll";
}
