{
  lib,
  ...
}:

with lib;

{
  options.myServices.backups = {
    mariadbDatabases = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "MariaDB databases to back up, contributed by service modules on this host.";
    };

    postgresqlDatabases = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "PostgreSQL databases to back up, contributed by service modules on this host.";
    };

    mongodbDatabases = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "MongoDB databases to back up, contributed by service modules on this host.";
    };

    sqliteDatabases = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = "SQLite databases to back up, contributed by service modules on this host.";
    };
  };
}
