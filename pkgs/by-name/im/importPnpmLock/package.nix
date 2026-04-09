{
  lib,
  stdenv,
  fetchurl,
  runCommand,
  yq-go,
  pnpmConfigHook,
  fetchPnpmDeps,
}:

let
  inherit (lib)
    hasPrefix
    importJSON
    mapAttrs
    optionalAttrs
    toJSON
    ;

  pnpmLockJSON =
    pnpmLock:
    runCommand "pnpm-lock.json" { src = pnpmLock; } ''
      ${lib.getExe yq-go} -o=json '.' < "$src" > "$out"
    '';

  getName = package: package.name or "unknown";
  getVersion = package: package.version or "0.0.0";
in
lib.fix (self: {
  importPnpmLock =
    {
      pnpmRoot ? null,
      package ? importJSON "${pnpmRoot}/package.json",
      pnpmLock ? importJSON (pnpmLockJSON "${pnpmRoot}/pnpm-lock.yaml"),
      pname ? getName package,
      version ? getVersion package,
      fetcherOpts ? { },
      packageSourceOverrides ? { },
      defaultRegistry ? "https://registry.npmjs.org",
    }:
    let
      rewrittenLock =
        pnpmLock
        // optionalAttrs (pnpmLock ? packages) {
          packages = mapAttrs (
            modulePath: module:
            let
              src =
                packageSourceOverrides.${modulePath} or (self.fetchPnpmModule {
                  inherit
                    modulePath
                    module
                    defaultRegistry
                    ;
                  fetcherOpts = fetcherOpts.${modulePath} or { };
                });
            in
            module
            // optionalAttrs (src != null) {
              resolution = (module.resolution or { }) // {
                tarball = "file:${src}";
              };
            }
          ) pnpmLock.packages;
        };
    in
    runCommand "${pname}-${version}-sources"
      {
        inherit pname version;

        passAsFile = [
          "package"
          "pnpmLock"
        ];

        package = toJSON package;
        pnpmLock = toJSON rewrittenLock;
      }
      ''
        mkdir -p "$out"
        cp "$packagePath" "$out/package.json"
        cp "$pnpmLockPath" "$out/pnpm-lock.yaml"
      '';

  fetchPnpmModule =
    {
      modulePath,
      module,
      fetcherOpts,
      defaultRegistry,
    }:
    let
      resolution = module.resolution or null;
      integrity = if resolution != null then resolution.integrity or null else null;
      tarball =
        if resolution != null && resolution ? tarball then
          resolution.tarball
        else
          self.makeTarballUrl {
            inherit
              modulePath
              module
              defaultRegistry
              ;
          };
    in
    if resolution == null then
      null
    else if integrity == null then
      throw ''
        importPnpmLock: `${modulePath}` has no resolution.integrity in pnpm-lock.yaml.

        Requires integrity for fixed-output fetching.
      ''
    else if hasPrefix "http://" tarball || hasPrefix "https://" tarball then
      fetchurl (
        {
          url = tarball;
          hash = integrity;
        }
        // fetcherOpts
      )
    else
      throw ''
        importPnpmLock: unsupported tarball source for `${modulePath}`: ${tarball}

        Only supports http(s) registry tarballs.
      '';

  parsePnpmPackageKey =
    modulePath:
    let
      m = builtins.match "^(.*)@([^()/]+)$" modulePath;
    in
    if m == null then
      throw "parsePnpmPackageKey: unsupported pnpm package key: ${modulePath}"
    else
      {
        name = builtins.elemAt m 0;
        version = builtins.elemAt m 1;
      };

  makeTarballUrl =
    {
      modulePath,
      module,
      defaultRegistry,
    }:
    if !(module ? resolution) then
      null
    else if module.resolution ? tarball then
      module.resolution.tarball
    else
      let
        parsed = self.parsePnpmPackageKey modulePath;

        name = parsed.name;
        version = parsed.version;

        scopeMatch = builtins.match "^(@[^/]+)/(.+)$" name;
        unscopedName = if scopeMatch == null then name else builtins.elemAt scopeMatch 1;

        normalizedRegistry =
          if builtins.substring ((builtins.stringLength defaultRegistry) - 1) 1 defaultRegistry == "/" then
            builtins.substring 0 ((builtins.stringLength defaultRegistry) - 1) defaultRegistry
          else
            defaultRegistry;
      in
      if hasPrefix "@" name && scopeMatch == null then
        throw "makeTarballUrl: invalid scoped package name for ${modulePath}: ${name}"
      else
        "${normalizedRegistry}/${name}/-/${unscopedName}-${version}.tgz";

  # Build node modules from package.json & pnpm-lock.yaml
  buildNodeModules =
    {
      pnpmRoot ? null,
      package ? importJSON "${pnpmRoot}/package.json",
      pnpmLock ? importJSON (pnpmLockJSON "${pnpmRoot}/pnpm-lock.yaml"),
      nodejs,
      pnpm,
      derivationArgs ? { },
    }:
    stdenv.mkDerivation (
      finalAttrs:
      {
        pname = derivationArgs.pname or "${getName package}-node-modules";
        version = derivationArgs.version or getVersion package;

        dontUnpack = true;

        pnpmDeps = fetchPnpmDeps {
          inherit (finalAttrs) pname version;
          src = self.importPnpmLock {
            inherit pnpmRoot package pnpmLock;
          };
          fetcherVersion = 3;
          fixedOutput = false;
        };

        package = toJSON package;
        pnpmLock = toJSON pnpmLock;

        installPhase = ''
          runHook preInstall
          mkdir $out
          cp package.json $out/
          cp pnpm-lock.yaml $out/
          [[ -d node_modules ]] && mv node_modules $out/
          runHook postInstall
        '';
      }
      // derivationArgs
      // {
        nativeBuildInputs = [
          nodejs
          pnpm
          pnpmConfigHook
        ]
        ++ derivationArgs.nativeBuildInputs or [ ];

        passAsFile = [
          "package"
          "pnpmLock"
        ]
        ++ derivationArgs.passAsFile or [ ];

        postPatch = ''
          cp --no-preserve=mode "$packagePath" package.json
          cp --no-preserve=mode "$pnpmLockPath" pnpm-lock.yaml
        ''
        + derivationArgs.postPatch or "";
      }
    );

  __functor = self: self.importPnpmLock;
})
