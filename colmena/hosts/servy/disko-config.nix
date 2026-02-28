{
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Samsung_SSD_870_EVO_500GB_S7EWNL0X701621J";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "2M";
              type = "EF02";
              priority = 1;
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
      sdb = {
        type = "disk";
        device = "/dev/disk/by-id/ata-TOSHIBA_MG09ACA18TE_X2N0A04YFJDH";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage_pool";
              };
            };
          };
        };
      };
      sdc = {
        type = "disk";
        device = "/dev/disk/by-id/ata-TOSHIBA_MG09ACA18TE_X2N0A05AFJDH";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "storage_pool";
              };
            };
          };
        };
      };
    };

    zpool = {
      storage_pool = {
        type = "zpool";
        mode = "raidz1";
        options = {
          ashift = "12";
        };
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
        };
        datasets = {
          data = {
            type = "zfs_fs";
            options = {
              encryption = "aes-256-gcm";
              keyformat = "passphrase";
              keylocation = "prompt";
              mountpoint = "/mnt/storage";
              # After initial setup, set the keylocation using the zfs command.
              # keylocation = "file:///run/secrets/zfs_storage_pool_key";
            };
          };
        };
      };
    };
  };
}
