# Nix Lab

This is the configuration of all my servers using NixOS.

## Architecture Overview

| Tool               | Responsibility                                                               | Running                                          |
| ------------------ | ---------------------------------------------------------------------------- | ------------------------------------------------ |
| **Terraform**      | Hardware provisioning (creates VMs, networks, SSH keys on Hetzner Cloud API) | Once per server creation/destruction             |
| **nixos-anywhere** | OS installation (wipes the disk, partitions it, installs NixOS from scratch) | Once per server (initial bootstrap)              |
| **Disko**          | Declarative disk partitioning (defines filesystems, mount points)            | Part of nixos-anywhere; embedded in NixOS config |
| **Colmena**        | Configuration deployment (applies NixOS config updates to running servers)   | Every time you change server configuration       |

## Getting Started

To get started using this repository, fill the required secrets.

### Backend Config

I am using Cloudflare R2 as the Terraform backend.
Navigate to the `terraform` folder, copy the `backend.conf.example` and fill the variables.

```shell
cd terraform
cp backend.conf.example backend.conf
```

If you want to use a different backend provider, change the `terraform.backend` section in the `main.tf` file.

### Secrets

I am deploying my servers on hetzner.
Navigate to the `terraform` folder, copy the `secrets.auto.tfvars.example` and fill the variables.

```shell
cd terraform
cp secrets.auto.tfvars.example secrets.auto.tfvars
```

## Working with existing servers

If your servers are already running NixOS (bootstrapped previously), use Colmena to deploy updates.

```bash
just deploy
```

You can also only apply to one server.

```bash
just deploy --on publy
```

You can also deploy by tag.

```bash
just deploy --on @public
```

## Bootstraping a new server

### Hetzner Cloud

#### 1. Configure the server

Add the new server to your Terraform variables `infrastructure.auto.tf`.

```tf
servers = {
  "my-new-server" = {
    server_type = "cx23"
    private_ip  = "10.0.1.3"
  }
}
```

View the available server types in the [Hetzner Cloud Console](https://console.hetzner.com) by creating a new server.

#### 2. Create the NixOS configuration

Create the NixOS configuration by copying the standard config from the `examples/hetzner` folder.

```shell
cd colmena/hosts
mkdir my-new-server
cd my-new-server
cp ../../examples/hetzner/* .
```

You also need to make sure all new files are added to git.

```shell
git add configuration.nix disko-config.nix hardware-configuration.nix
```

#### 3. Register the host in the flake

Edit `colmena/flake.nix` and add your host to `hostModules`:

```nix
{
hostModules = {
  publy = [ /* ... */ ];

  my-new-server = [
    sops-nix.nixosModules.sops
    disko.nixosModules.disko
    ./hosts/my-new-server/disko-config.nix
    ./hosts/my-new-server/configuration.nix
    (
      { ... }:
      {
        networking.hostName = "my-new-server";
      }
    )
  ];
};
}
```

Then add it to both `nixosConfigurations` and `colmena.outputs`:

```nix
{
nixosConfigurations = {
  publy = nixpkgs.lib.nixosSystem { /* ... */ };

  my-new-server = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = hostModules.my-new-server;
  };
};

colmena = {
  publy =
    { ... }:
    { /* ... */ };

  my-new-server =
    { ... }:
    {
      deployment.targetHost = serverIps.my-new-server;
      deployment.tags = [
        "web"
        "public"
      ];
      imports = hostModules.my-new-server;
    };
};
}
```

#### 4. Provision and bootstrap

```shell
just tf-apply

just bootstrap my-new-server
```

#### 5. Add it's sops key

Get the servers age key and add it to the `.sops.yaml` file.

```shell
just get-age-key my-new-server
```

```yaml
keys:
  # Clients
  # ...
  # Servers
  # ...
  - &my-new-server age14...
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          # ...
          - *my-new-server
```

Next, you need to update the keys for the existing secret files:

```shell
just update-keys
```

#### 6. Run Colmena

```shell
just deploy
```

### Hardware

Non-cloud hardware cannot be configured using terraform.
However you can still use most of the tooling in this repository.

### 1. Installing the Server

Install debian on the server and make sure it can be accessed using your ssh key.

### 2. Create the NixOS configuration

Create the NixOS configuration by copying the standard config from the `examples/hetzner` folder.

```shell
cd colmena/hosts
mkdir my-new-server
cd my-new-server
cp ../../examples/hetzner/* .
```

Make sure to change the `disko-config.nix` to use the correct devices and make other changes specific to your hardware.

You also need to make sure all new files are added to git.

```shell
git add configuration.nix disko-config.nix hardware-configuration.nix
```

### 3. Register the host in the flake

Edit `colmena/flake.nix` and add your host to `hostModules`:

```nix
{
hostModules = {
  publy = [ /* ... */ ];

  my-new-server = [
    sops-nix.nixosModules.sops
    disko.nixosModules.disko
    ./hosts/my-new-server/disko-config.nix
    ./hosts/my-new-server/configuration.nix
    (
      { ... }:
      {
        networking.hostName = "my-new-server";
      }
    )
  ];
};
}
```

Then add it to both `nixosConfigurations` and `colmena.outputs`:

```nix
{
nixosConfigurations = {
  publy = nixpkgs.lib.nixosSystem { /* ... */ };

  my-new-server = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = hostModules.my-new-server;
  };
};

colmena = {
  publy =
    { ... }:
    { /* ... */ };

  my-new-server =
    { ... }:
    {
      deployment.targetHost = serverIps.my-new-server;
      deployment.tags = [
        "web"
        "public"
      ];
      imports = hostModules.my-new-server;
    };
};
}
```

### 4. Bootstrap

```shell
just bootstrap my-new-server
```

#### 5. Add it's sops key

Get the servers age key and add it to the `.sops.yaml` file.

```shell
just get-age-key my-new-server
```

```yaml
keys:
  # Clients
  # ...
  # Servers
  # ...
  - &my-new-server age14...
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          # ...
          - *my-new-server
```

Next, you need to update the keys for the existing secret files:

```shell
just update-keys
```

#### 6. Run Colmena

```shell
just deploy
```

## Troubleshooting

### Container does not start

```shell
journalctl -eu podman-beszel-agent.service -f
```

### Colmena could not aquire lock

```shell
[root@publy:/mnt/storage/containers]# ps aux | grep nixos
root       41619  0.0  0.1   9340  5628 ?        Ss   12:56   0:00 /nix/store/d8z6sjjp0adn28q04bsrz2i6z942xz8y-nixos-system-publy-26.05pre-git/bin/switch-to-configuration switch
root       48036  0.0  0.0   6884  2872 pts/0    S+   13:29   0:00 grep nixos

[root@publy:/mnt/storage/containers]# sudo pkill -f switch
```
