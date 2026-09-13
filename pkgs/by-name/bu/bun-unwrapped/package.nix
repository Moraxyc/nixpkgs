{
  lib,
  stdenv,
  callPackage,
  linkFarm,
  symlinkJoin,
  fetchFromGitHub,
  fetchurl,
  gitMinimal,
  installShellFiles,
  versionCheckHook,
  cmake,
  ninja,
  go,
  perl,
  nasm,
  rustc,
  cargo,
  rustPlatform,
  llvmPackages,
  icu,
  bun-bin,
  bun-webkit,
  esbuild,
  cctools,
  darwin,
  rcodesign,
  sqlite,
  readline,
  libedit,
}:

let
  inherit (stdenv.hostPlatform)
    isLinux
    isDarwin
    isMusl
    ;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "bun-unwrapped";
  version = finalAttrs.passthru.sources.version;

  src = fetchFromGitHub {
    owner = "oven-sh";
    repo = "bun";
    rev = finalAttrs.passthru.sources.revision;
    hash = finalAttrs.passthru.sources.sourceHash;
  };

  __structuredAttrs = true;
  strictDeps = true;

  patches = [
    # Keep dependency installation offline and adapt ABI and toolchain settings.
    ./support-nix-build-environment.patch

    # Use prebuilt WebKit from bun-webkit derivation and system ICU
    ./use-nix-webkit.patch
  ];

  disallowedReferences = [ bun-bin ];
  disallowedRequisites = [ bun-bin ];

  cargoDeps = rustPlatform.fetchCargoVendor {
    pname = "bun-cargo-deps";
    inherit (finalAttrs) version src;
    hash = finalAttrs.passthru.sources.cargoHash;
  };

  nativeBuildInputs = [
    bun-bin
    installShellFiles
    cmake
    ninja
    gitMinimal
    go
    perl
    nasm
    llvmPackages.clang
    rustc
    cargo
    rustPlatform.cargoSetupHook
    esbuild
  ]
  ++ lib.optionals isDarwin [
    cctools
    darwin.bootstrap_cmds
    rcodesign
  ];

  buildInputs = [
    bun-webkit
  ]
  ++ lib.optionals isLinux [ icu ]
  ++ lib.optionals isDarwin [
    darwin.ICU
    (lib.getDev sqlite)
    (lib.getDev readline)
    (lib.getLib libedit)
  ];

  dontConfigure = true;

  dontPatchELF = isLinux;
  hardeningDisable = [ "fortify" ];

  env = {
    GIT_SHA = finalAttrs.passthru.sources.revision;
    NIX_CFLAGS_COMPILE = "-gz=zlib";
    NIX_LDFLAGS = lib.concatStringsSep " " (
      lib.optionals isLinux [
        "--disable-new-dtags"
        "-rpath"
        (lib.makeLibraryPath [
          stdenv.cc.cc
          icu
        ])
      ]
      ++ lib.optionals isDarwin [ "-rename_segment __DATA_DIRTY __DATA" ]
    );
    BUN_WEBKIT_DIR = "${bun-webkit}";
    BUN_NIX_ABI = lib.optionalString isLinux (if isMusl then "musl" else "gnu");
    BUN_NIX_CROSS = lib.optionalString (
      isLinux && stdenv.buildPlatform.system != stdenv.hostPlatform.system
    ) "1";
    RUSTC_BOOTSTRAP = 1;
    BUN_BUILD_PREFETCH_DIR = finalAttrs.passthru.buildPrefetch;
    BUN_TOOLCHAIN_LLVM = finalAttrs.passthru.llvmToolchain;
    BUN_ESBUILD_BIN = lib.getExe esbuild;
  };

  preBuild = ''
    cp -R "${finalAttrs.passthru.nodeModules}/node_modules" node_modules
    cp -R "${finalAttrs.passthru.nodeModules}/packages/bun-error/node_modules" packages/bun-error/node_modules
    cp -R "${finalAttrs.passthru.nodeModules}/src/node-fallbacks/node_modules" src/node-fallbacks/node_modules
    chmod -R u+w node_modules packages/bun-error/node_modules src/node-fallbacks/node_modules

    mkdir -p node_modules/.bin
    ln -sf "${lib.getExe esbuild}" node_modules/.bin/esbuild

    export HOME="$TMPDIR/home"
    export BUN_INSTALL="$TMPDIR/bun-install"
    export CARGO_HOME="$TMPDIR/cargo-home"
    export RUSTUP_HOME="$TMPDIR/rustup-home"
    mkdir -p "$HOME" "$BUN_INSTALL" "$CARGO_HOME" "$RUSTUP_HOME"
  '';

  buildPhase = ''
    runHook preBuild

    buildArgs=(
      --os=${stdenv.hostPlatform.parsed.kernel.name}
      --arch=${if stdenv.hostPlatform.isAarch64 then "aarch64" else "x64"}
      --profile=release
      --canary=off
      --webkit=prebuilt
      --static-libatomic=off
      --cache-dir="$TMPDIR/bun-build-cache"
      -j"$NIX_BUILD_CORES"
    )
  ''
  + lib.optionalString isLinux ''
    buildArgs+=(--abi=${if isMusl then "musl" else "gnu"})
  ''
  + ''
    bun scripts/build.ts "''${buildArgs[@]}"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 build/release/bun "$out/bin/bun"
    ln -s bun "$out/bin/bunx"
    installShellCompletion --cmd bun \
      --bash completions/bun.bash \
      --fish completions/bun.fish \
      --zsh completions/bun.zsh

    runHook postInstall
  '';

  postFixup = lib.optionalString isDarwin ''
    '${lib.getExe' cctools "${cctools.targetPrefix}install_name_tool"}' "$out/bin/bun" \
      -change /usr/lib/libicucore.A.dylib '${lib.getLib darwin.ICU}/lib/libicucore.A.dylib'
    '${lib.getExe rcodesign}' sign --code-signature-flags linker-signed "$out/bin/bun"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  __darwinAllowLocalNetworking = true;
  installCheckPhase = ''
    runHook preInstallCheck
  ''
  # JavaScriptCore and ICU. The upstream libc probe hardcodes /usr/lib/libc.so
  # on musl, which does not exist in Nix; keep the other 32 Intl tests.
  + lib.optionalString isMusl ''
    CI=1 "$out/bin/bun" test test/js/web/intl/intl.test.ts \
      --test-name-pattern='^(?!.*default locale under C\.UTF-8).*$'
  ''
  + lib.optionalString (!isMusl) ''
    CI=1 "$out/bin/bun" test test/js/web/intl/intl.test.ts
  ''
  + ''
    # JIT, WebAssembly, SQLite and compiled executables.
    CI=1 "$out/bin/bun" test \
      test/regression/issue/32793.test.ts \
      test/regression/issue/14709.test.ts \
      test/js/web/fetch/wasm-streaming.test.ts \
      test/bundler/bun-build-compile-wasm.test.ts

    # Runtime, TypeScript and module loading.
    CI=1 "$out/bin/bun" test test/cli/run/run-eval.test.ts

    # Offline workspace installation.
    CI=1 "$out/bin/bun" test test/regression/issue/3192.test.ts

    # Bundling with code splitting.
    CI=1 "$out/bin/bun" test test/regression/issue/5344.test.ts
  ''
  # Native compilation and signal handling through bun:ffi.
  + lib.optionalString isLinux ''
    CI=1 \
      C_INCLUDE_PATH="${lib.getDev stdenv.cc.libc}/include" \
      LIBRARY_PATH="${lib.getLib stdenv.cc.libc}/lib" \
      "$out/bin/bun" test test/regression/issue/20144/20144.test.ts
  ''
  + lib.optionalString isDarwin ''
    CI=1 "$out/bin/bun" test test/regression/issue/20144/20144.test.ts
  ''
  + ''
    runHook postInstallCheck
  '';

  passthru = {
    sources = lib.importJSON ./sources.json;

    llvmToolchain = symlinkJoin {
      name = "bun-llvm-toolchain";
      paths = with llvmPackages; [
        clang
        llvm
        lld
      ];
    };

    nodeModules = callPackage ./node-modules.nix { } {
      inherit (finalAttrs) version src;
      hash = finalAttrs.passthru.sources.nodeModulesHash;
    };

    buildPrefetch = linkFarm "bun-build-prefetch-${finalAttrs.version}" (
      map (download: {
        name = "by-url/${lib.substring 0 32 (lib.hashString "sha256" download.url)}";
        path = fetchurl {
          inherit (download) url hash;
          name = "bun-${download.name}.tar.gz";
        };
      }) finalAttrs.passthru.sources.downloads
    );
    updateScript = ./update.py;
  };

  meta = {
    homepage = "https://bun.sh";
    changelog = "https://bun.sh/blog/bun-v${finalAttrs.version}";
    description = "Incredibly fast JavaScript runtime, bundler, transpiler and package manager – all in one";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      DAlperin
      jk
      thilobillerbeck
      cdmistman
      diogomdp
    ];
    mainProgram = "bun";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
