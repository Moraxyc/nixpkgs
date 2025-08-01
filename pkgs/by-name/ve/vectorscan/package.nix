{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  ragel,
  util-linux,
  python3,
  boost,
  sqlite,
  pcre,
  enableShared ? !stdenv.hostPlatform.isStatic,
}:

stdenv.mkDerivation rec {
  pname = "vectorscan";
  version = "5.4.12";

  src = fetchFromGitHub {
    owner = "VectorCamp";
    repo = "vectorscan";
    rev = "vectorscan/${version}";
    hash = "sha256-P/3qmgVZ9OLfJGfxsKJ6CIuaKuuhs1nJt4Vjf1joQDc=";
  };

  postPatch = ''
    sed -i '/examples/d' CMakeLists.txt
    substituteInPlace libhs.pc.in \
      --replace-fail "libdir=@CMAKE_INSTALL_PREFIX@/@CMAKE_INSTALL_LIBDIR@" "libdir=@CMAKE_INSTALL_LIBDIR@" \
      --replace-fail "includedir=@CMAKE_INSTALL_PREFIX@/@CMAKE_INSTALL_INCLUDEDIR@" "includedir=@CMAKE_INSTALL_INCLUDEDIR@"
    substituteInPlace cmake/build_wrapper.sh \
      --replace-fail 'nm' '${stdenv.cc.targetPrefix}nm' \
      --replace-fail 'objcopy' '${stdenv.cc.targetPrefix}objcopy'
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    ragel
    python3
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux util-linux;

  buildInputs = [
    boost
    sqlite
    pcre
  ];

  # FAT_RUNTIME bundles optimized implementations for different CPU extensions and uses CPUID to
  # transparently select the fastest for the current hardware.
  # This feature is only available on linux for x86, x86_64, and aarch64.
  #
  # If FAT_RUNTIME is not available, we fall back to building for a single extension based
  # on stdenv.hostPlatform.
  #
  # For generic builds (e.g. x86_64) this can mean using an implementation not optimized for the
  # potentially available more modern hardware extensions (e.g. x86_64 with AVX512).
  cmakeFlags = [
    "-DBUILD_BENCHMARKS=OFF"
    (if enableShared then "-DBUILD_SHARED_LIBS=ON" else "BUILD_STATIC_LIBS=ON")
  ]
  ++ (
    if
      lib.elem stdenv.hostPlatform.system [
        "x86_64-linux"
        "i686-linux"
      ]
    then
      [
        "-DBUILD_AVX2=ON"
        "-DBUILD_AVX512=ON"
        "-DBUILD_AVX512VBMI=ON"
        "-DFAT_RUNTIME=ON"
      ]
    else
      (
        if (stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64) then
          [
            "-DBUILD_SVE=ON"
            "-DBUILD_SVE2=ON"
            "-DBUILD_SVE2_BITPERM=ON"
            "-DFAT_RUNTIME=ON"
          ]
        else
          [ "-DFAT_RUNTIME=OFF" ]
          ++ lib.optional stdenv.hostPlatform.avx2Support "-DBUILD_AVX2=ON"
          ++ lib.optional stdenv.hostPlatform.avx512Support "-DBUILD_AVX512=ON"
      )
  );

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    ./bin/unit-hyperscan

    runHook postCheck
  '';

  meta = with lib; {
    description = "Portable fork of the high-performance regular expression matching library";
    longDescription = ''
      A fork of Intel's Hyperscan, modified to run on more platforms. Currently
      ARM NEON/ASIMD is 100% functional, and Power VSX are in development.
      ARM SVE2 will be implemented when hardware becomes accessible to the
      developers. More platforms will follow in the future, on demand/request.

      Vectorscan will follow Intel's API and internal algorithms where possible,
      but will not hesitate to make code changes where it is thought of giving
      better performance or better portability. In addition, the code will be
      gradually simplified and made more uniform and all architecture specific
      code will be abstracted away.
    '';
    homepage = "https://www.vectorcamp.gr/vectorscan/";
    changelog = "https://github.com/VectorCamp/vectorscan/blob/${src.rev}/CHANGELOG-vectorscan.md";
    platforms = platforms.unix;
    license = with licenses; [
      bsd3 # and
      bsd2 # and
      licenses.boost
    ];
    maintainers = with maintainers; [
      tnias
      vlaci
    ];
  };
}
