{
  lib,
  clangStdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  bison,
  gawk,
  gperf,
  python3,
  ruby,
  perl,
  icu,
  libxml2,
  zlib,
  darwin,
  cctools,
  sqlite,
  readline,
  libedit,
}:

let
  inherit (clangStdenv.hostPlatform) isLinux isDarwin;
in
clangStdenv.mkDerivation (finalAttrs: {
  pname = "bun-webkit";
  version = finalAttrs.passthru.webkit.version;

  src = fetchFromGitHub {
    owner = "oven-sh";
    repo = "WebKit";

    inherit (finalAttrs.passthru.webkit)
      rev
      hash
      sparseCheckout
      ;
  };

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    bison
    gawk
    gperf
    python3
    ruby
    perl
  ]
  ++ lib.optionals isDarwin [
    cctools
    darwin.bootstrap_cmds
  ];

  buildInputs = [
    icu
    libxml2
    zlib
  ]
  ++ lib.optionals isDarwin [
    darwin.ICU
    sqlite
    readline
    libedit
  ];

  cmakeFlags = [
    (lib.cmakeFeature "PORT" "JSCOnly")
    (lib.cmakeBool "ENABLE_STATIC_JSC" true)
    (lib.cmakeBool "USE_THIN_ARCHIVES" false)
    (lib.cmakeBool "ENABLE_FTL_JIT" true)
    (lib.cmakeBool "ENABLE_TOOLS" false)
    (lib.cmakeBool "ENABLE_API_TESTS" false)
    (lib.cmakeBool "USE_BUN_JSC_ADDITIONS" true)
    (lib.cmakeBool "USE_BUN_EVENT_LOOP" true)
    (lib.cmakeBool "USE_MIMALLOC" true)
    (lib.cmakeBool "USE_EXTERNAL_MIMALLOC" true)
    (lib.cmakeBool "ENABLE_BUN_SKIP_FAILING_ASSERTIONS" true)
    (lib.cmakeBool "ALLOW_LINE_AND_COLUMN_NUMBER_IN_BUILTINS" true)
    (lib.cmakeBool "ENABLE_REMOTE_INSPECTOR" true)
    (lib.cmakeBool "ENABLE_MEDIA_SOURCE" false)
    (lib.cmakeBool "ENABLE_MEDIA_STREAM" false)
    (lib.cmakeBool "ENABLE_WEB_RTC" false)
  ]
  ++ lib.optionals isLinux [
    (lib.cmakeBool "CMAKE_POSITION_INDEPENDENT_CODE" false)
  ]
  ++ lib.optionals isDarwin [
    (lib.cmakeFeature "CMAKE_OSX_SYSROOT" "")
    (lib.cmakeFeature "CMAKE_Swift_COMPILER" "${clangStdenv.cc}/bin/clang")
    (lib.cmakeFeature "GPERF_EXECUTABLE" (lib.getExe gperf))
    (lib.cmakeFeature "Mig_EXECUTABLE" (lib.getExe' darwin.bootstrap_cmds "mig"))
  ];

  ninjaFlags = [ "jsc" ];

  env = {
    NIX_CFLAGS_COMPILE = lib.concatStringsSep " " [
      "-gz=zlib"
      "-ffile-prefix-map=${finalAttrs.src}/Source=vendor/WebKit/Source"
    ];
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/include
    # Bun's root.h includes WebKit's generated configuration header.
    install -Dm644 cmakeconfig.h $out/include/cmakeconfig.h
    cp lib/lib*.a $out/lib/

    for d in JavaScriptCore/Headers JavaScriptCore/PrivateHeaders WTF/Headers bmalloc/Headers; do
      if [ -d "$d" ]; then
        cp -rL "$d"/* $out/include/
      fi
    done

    mkdir -p $out/JavaScriptCore $out/WTF $out/bmalloc
    [ -d JavaScriptCore/Headers ] && cp -rL JavaScriptCore/Headers $out/JavaScriptCore/
    [ -d JavaScriptCore/PrivateHeaders ] && cp -rL JavaScriptCore/PrivateHeaders $out/JavaScriptCore/
    [ -d WTF/Headers ] && cp -rL WTF/Headers $out/WTF/
    [ -d bmalloc/Headers ] && cp -rL bmalloc/Headers $out/bmalloc/

    echo "nix" > $out/.identity

    runHook postInstall
  '';

  passthru = {
    webkit = (lib.importJSON ../bun-unwrapped/sources.json).webkit;
  };

  meta = {
    description = "WebKit JavaScriptCore built for Bun";
    homepage = "https://github.com/oven-sh/WebKit";
    license = lib.licenses.lgpl21Only;
    platforms = lib.platforms.unix;
  };
})
