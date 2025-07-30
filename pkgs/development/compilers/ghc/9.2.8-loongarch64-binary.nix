{
  lib,
  stdenv,
  fetchurl,
  perl,
  ncurses6,
  gmp,
  numactl,
  libffi,
  llvmPackages,
  coreutils,
  targetPackages,

  # minimal = true; will remove files that aren't strictly necessary for
  # regular builds and GHC bootstrapping.
  # This is "useful" for staying within hydra's output limits for at least the
  # aarch64-linux architecture.
  minimal ? false,
}:

# Prebuilt only does native
assert stdenv.targetPlatform == stdenv.hostPlatform;

# Only build on LoongArch64 for scripts in installCheckPhase
assert stdenv.hostPlatform.isLoongArch64;
assert stdenv.hostPlatform.isGnu;

let
  version = "9.2.8";

  ghcBinDists = {
    loongarch64-linux = {
      variantSuffix = "";
      src = {
        url = "http://tarballs.nixos.org/stdenv/loongarch64-linux/fakehash/ghc-9.2.8.tar.xz";
        sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
      };
      archSpecificLibraries = [
        {
          nixPackage = gmp;
          fileToCheckFor = null;
        }
        {
          nixPackage = ncurses6;
          fileToCheckFor = "libtinfo.so.6";
        }
        {
          nixPackage = numactl;
          fileToCheckFor = null;
        }
        {
          nixPackage = libffi;
          fileToCheckFor = null;
        }
      ];
    };
  };

  binDistUsed =
    ghcBinDists.${stdenv.hostPlatform.system}
      or (throw "cannot bootstrap GHC on this platform ('${stdenv.hostPlatform.system}')");

  gmpUsed =
    (builtins.head (
      builtins.filter (
        drv: lib.hasPrefix "gmp" (drv.nixPackage.name or "")
      ) binDistUsed.archSpecificLibraries
    )).nixPackage;

  libPath = lib.makeLibraryPath (
    # Add arch-specific libraries.
    map ({ nixPackage, ... }: nixPackage) binDistUsed.archSpecificLibraries
  );

  runtimeDeps = [
    targetPackages.stdenv.cc
    targetPackages.stdenv.cc.bintools
    coreutils # for cat
  ];

in

stdenv.mkDerivation {
  inherit version;
  pname = "ghc-binary${binDistUsed.variantSuffix}";

  src = fetchurl binDistUsed.src;

  nativeBuildInputs = [
    perl
    stdenv.cc.bintools
  ];

  # Set LD_LIBRARY_PATH or equivalent so that the programs running as part
  # of the bindist installer can find the libraries they expect.
  # Cannot patchelf beforehand due to relative RPATHs that anticipate
  # the final install location.
  LD_LIBRARY_PATH = libPath;

  postUnpack =
    # Some scripts used during the build need to have their shebangs patched
    ''
      patchShebangs ghc-${version}/utils/
      patchShebangs ghc-${version}/configure
      test -d ghc-${version}/inplace/bin && \
        patchShebangs ghc-${version}/inplace/bin
    ''
    +
      # We have to patch the GMP paths for the integer-gmp package.
      ''
        find . -name ghc-bignum.buildinfo \
            -exec sed -i "s@extra-lib-dirs: @extra-lib-dirs: ${lib.getLib gmpUsed}/lib@" {} \;

        # we need to modify the package db directly for hadrian bindists
        find . -name 'ghc-bignum*.conf' \
            -exec sed -e '/^[a-z-]*library-dirs/a \    ${lib.getLib gmpUsed}/lib' -i {} \;
      ''
    +
      # Some platforms do HAVE_NUMA so -lnuma requires it in library-dirs in rts/package.conf.in
      # FFI_LIB_DIR is a good indication of places it must be needed.
      lib.optionalString
        (
          lib.meta.availableOn stdenv.hostPlatform numactl
          && builtins.any ({ nixPackage, ... }: nixPackage == numactl) binDistUsed.archSpecificLibraries
        )
        ''
          find . -name package.conf.in \
              -exec sed -i "s@FFI_LIB_DIR@FFI_LIB_DIR ${numactl.out}/lib@g" {} \;
        ''
    +
      # Rename needed libraries and binaries, fix interpreter
      lib.optionalString stdenv.hostPlatform.isLinux ''
        find . -type f -executable -exec patchelf \
            --interpreter ${stdenv.cc.bintools.dynamicLinker} {} \;
      '';

  # fix for `configure: error: Your linker is affected by binutils #16177`
  preConfigure = lib.optionalString stdenv.targetPlatform.isAarch32 "LD=ld.gold";

  configurePlatforms = [ ];
  configureFlags = [
    "--with-gmp-includes=${lib.getDev gmpUsed}/include"
    # Note `--with-gmp-libraries` does nothing for GHC bindists:
    # https://gitlab.haskell.org/ghc/ghc/-/merge_requests/6124
  ]
  ++ lib.optional stdenv.hostPlatform.isDarwin "--with-gcc=${./gcc-clang-wrapper.sh}"
  # From: https://github.com/NixOS/nixpkgs/pull/43369/commits
  ++ lib.optional stdenv.hostPlatform.isMusl "--disable-ld-override";

  # No building is necessary, but calling make without flags ironically
  # calls install-strip ...
  dontBuild = true;

  # Patch scripts to include runtime dependencies in $PATH.
  postInstall = ''
    for i in "$out/bin/"*; do
      test ! -h "$i" || continue
      isScript "$i" || continue
      sed -i -e '2i export PATH="${lib.makeBinPath runtimeDeps}:$PATH"' "$i"
    done
  '';

  dontStrip = false;

  # On Linux, use patchelf to modify the executables so that they can
  # find editline/gmp.
  postFixup =
    lib.optionalString (stdenv.hostPlatform.isLinux && !(binDistUsed.isStatic or false)) (
      if stdenv.hostPlatform.isAarch64 then
        # Keep rpath as small as possible on aarch64 for patchelf#244.  All Elfs
        # are 2 directories deep from $out/lib, so pooling symlinks there makes
        # a short rpath.
        ''
          (cd $out/lib; ln -s ${ncurses6.out}/lib/libtinfo.so.6)
          (cd $out/lib; ln -s ${lib.getLib gmpUsed}/lib/libgmp.so.10)
          (cd $out/lib; ln -s ${numactl.out}/lib/libnuma.so.1)
          for p in $(find "$out/lib" -type f -name "*\.so*"); do
            (cd $out/lib; ln -s $p)
          done

          for p in $(find "$out/lib" -type f -executable); do
            if isELF "$p"; then
              echo "Patchelfing $p"
              patchelf --set-rpath "\$ORIGIN:\$ORIGIN/../.." $p
            fi
          done
        ''
      else
        ''
          for p in $(find "$out" -type f -executable); do
            if isELF "$p"; then
              echo "Patchelfing $p"
              patchelf --set-rpath "${libPath}:$(patchelf --print-rpath $p)" $p
            fi
          done
        ''
    )
    + lib.optionalString minimal ''
      # Remove profiling files
      find $out -type f -name '*.p_o' -delete
      find $out -type f -name '*.p_hi' -delete
      find $out -type f -name '*_p.a' -delete
      # `-f` because e.g. musl bindist does not have this file.
      rm -f $out/lib/ghc-*/bin/ghc-iserv-prof
      # Hydra will redistribute this derivation, so we have to keep the docs for
      # legal reasons (retaining the legal notices etc)
      # As a last resort we could unpack the docs separately and symlink them in.
      # They're in $out/share/{doc,man}.
    ''
    # Recache package db which needs to happen for Hadrian bindists
    # where we modify the package db before installing
    + ''
      shopt -s nullglob
      package_db=("$out"/lib/ghc-*/lib/package.conf.d "$out"/lib/ghc-*/package.conf.d)
      "$out/bin/ghc-pkg" --package-db="$package_db" recache
    '';

  # GHC cannot currently produce outputs that are ready for `-pie` linking.
  # Thus, disable `pie` hardening, otherwise `recompile with -fPIE` errors appear.
  # See:
  # * https://github.com/NixOS/nixpkgs/issues/129247
  # * https://gitlab.haskell.org/ghc/ghc/-/issues/19580
  hardeningDisable = [ "pie" ];

  doInstallCheck = true;
  installCheckPhase = ''
    # Sanity check, can ghc create executables?
    cd $TMP
    mkdir test-ghc; cd test-ghc
    cat > main.hs << EOF
      {-# LANGUAGE TemplateHaskell #-}
      module Main where
      main = putStrLn \$([|"yes"|])
    EOF
    env -i $out/bin/ghc --make main.hs || exit 1
    echo compilation ok
    [ $(./main) == "yes" ]
  '';

  passthru = {
    targetPrefix = "";
    enableShared = true;

    inherit llvmPackages;

    # Our Cabal compiler name
    haskellCompilerName = "ghc-${version}";
  };

  meta = {
    homepage = "http://haskell.org/ghc";
    description = "Glasgow Haskell Compiler";
    license = lib.licenses.bsd3;
    # HACK: since we can't encode the libc / abi in platforms, we need
    # to make the platform list dependent on the evaluation platform
    # in order to avoid eval errors with musl which supports less
    # platforms than the default libcs (i. e. glibc / libSystem).
    # This is done for the benefit of Hydra, so `packagePlatforms`
    # won't return any platforms that would cause an evaluation
    # failure for `pkgsMusl.haskell.compiler.ghc922Binary`, as
    # long as the evaluator runs on a platform that supports
    # `pkgsMusl`.
    platforms = [ stdenv.hostPlatform.system ];
    teams = with lib.teams; [
      haskell
      loongarch64
    ];
  };
}
