{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.sub-store;
  format = pkgs.formats.keyValue { };
in
{
  meta.maintainers = with lib.maintainers; [ moraxyc ];

  options.services.sub-store = {
    enable = lib.mkEnableOption "sub-store service";

    package = lib.mkPackageOption pkgs "sub-store" { };

    frontendPackage = lib.mkPackageOption pkgs "sub-store-frontend" { nullable = true; };

    host = lib.mkOption {
      type = lib.types.str;
      default = "::";
      description = "The host address to bind to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "The backend API port.";
    };

    frontendPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "The frontend port.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an environment file loaded for the Sub-Store service.

        This can be used to securely store tokens and secrets outside of the world-readable Nix store.

        Example contents of the file:
        SUB_STORE_FRONTEND_BACKEND_PATH=/random-path-for-security
        SUB_STORE_BACKEND_MERGE=true
      '';
      default = "/dev/null";
      example = "/run/secrets/sub-store";
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = format.type;
      };
      default = { };
      description = ''
        Environment variables passed to the Sub-Store service.

        ::: {.note}
        If {option}`settings.SUB_STORE_BACKEND_MERGE` is set to `true`:
        - {env}`SUB_STORE_FRONTEND_BACKEND_PATH` must start with a forward slash (`/`).
        - {option}`services.sub-store.frontendPort` will be ignored as the frontend is served by the backend.
        :::

        Since {env}`SUB_STORE_FRONTEND_BACKEND_PATH` or other variables may contain sensitive
        information, it is highly recommended to provide them via
        {option}`services.sub-store.environmentFile` to avoid leaking secrets into the
        world-readable Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.sub-store = {
      description = "Sub-Store Service";
      after = [ "network.target" ];
      requires = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [
        cfg.package
        cfg.environmentFile
      ];

      environment = {
        SUB_STORE_FRONTEND_HOST = cfg.host;
        SUB_STORE_FRONTEND_PORT = toString cfg.frontendPort;
        SUB_STORE_BACKEND_API_HOST = cfg.host;
        SUB_STORE_BACKEND_API_PORT = toString cfg.port;
        SUB_STORE_DATA_BASE_PATH = "%S/sub-store";
      }
      // lib.optionalAttrs (cfg.frontendPackage != null) {
        SUB_STORE_FRONTEND_PATH = "${cfg.frontendPackage}";
      }
      // cfg.settings;

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        Type = "simple";
        Restart = "on-failure";
        EnvironmentFile = [ cfg.environmentFile ];

        DynamicUser = true;
        StateDirectory = "sub-store";
        StateDirectoryMode = "0700";
        WorkingDirectory = "%S/sub-store";

        # Security hardening
        CapabilityBoundingSet = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # Required for Node.js JIT
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        UMask = "0077";
      };
    };
  };
}
