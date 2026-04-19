# WireGuard Server Tunnel

WireGuard tunnel for connecting home servers to publy (VPS). Publy acts as the server/listener, home servers connect as clients.

## Architecture

- **publy** (server) - listens on UDP 51820, has a public IP
- **servy, raspy, ...** (clients) - initiate connections from behind NAT, use `persistentKeepalive = 25`

Subnet: `192.168.60.0/24`

| Host  | Address      |
| ----- | ------------ |
| publy | 192.168.60.1 |
| servy | 192.168.60.2 |

## Setting up the server (publy)

### 1. Generate a keypair

Can be done on any machine with `wireguard-tools` installed:

```bash
wg genkey | tee server.key | wg pubkey > server.pub
```

### 2. Add the private key to sops

```yaml
# colmena/secrets/publy.yaml
wireguard_private_key: <contents of server.key>
```

### 3. Enable the module

In `colmena/hosts/publy/configuration.nix`:

```nix
myServices.wireguard = {
  enable = true;
  sopsFile = ../../secrets/publy.yaml;

  address = "192.168.60.1/24";
  listenPort = 51820;

  peers = [
    # Add client peers here (see below)
  ];
};
```

### 4. Deploy and shred

```bash
just deploy --on publy
shred -u server.key server.pub
```

Save the public key before shredding - clients need it.

## Adding a client

### 1. Generate a keypair

```bash
wg genkey | tee client.key | wg pubkey > client.pub
```

### 2. Add the private key to sops

```yaml
# colmena/secrets/<host>.yaml
wireguard_private_key: <contents of client.key>
```

### 3. Pick an IP and add a peer entry on the server

Choose the next free IP in `192.168.60.0/24` and add a peer to publy's config:

```nix
# In publy's myServices.wireguard.peers
{
  publicKey = "<contents of client.pub>";
  allowedIPs = [ "192.168.60.X/32" ];
}
```

### 4. Enable the module on the client

In `colmena/hosts/<host>/configuration.nix`:

```nix
myServices.wireguard = {
  enable = true;
  sopsFile = ../../secrets/<host>.yaml;

  address = "192.168.60.X/24";

  peers = [
    {
      publicKey = "<publy's public key>";
      allowedIPs = [ "192.168.60.0/24" ];
      endpoint = "202.61.254.52:51820";
      persistentKeepalive = 25;
    }
  ];
};
```

### 5. Deploy and shred

```bash
just deploy --on host
shred -u client.key client.pub
```

### 6. Verify

```bash
# From the client
ping 192.168.60.1

# From publy
ping 192.168.60.X
```
