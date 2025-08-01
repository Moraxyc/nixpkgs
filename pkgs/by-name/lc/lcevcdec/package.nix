{
  cmake,
  fetchFromGitHub,
  git,
  gitUpdater,
  fetchpatch,
  lib,
  nlohmann_json,
  pkg-config,
  python3,
  stdenv,
  testers,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "lcevcdec";
  version = "3.3.8";

  outputs = [
    "out"
    "lib"
    "dev"
  ];

  src = fetchFromGitHub {
    owner = "v-novaltd";
    repo = "LCEVCdec";
    tag = finalAttrs.version;
    hash = "sha256-s7gY3l5ML+7T7i6DsstC75XXgxQgTWyITfa+8OhHl+w=";
  };

  patches = [
    (fetchpatch {
      url = "https://aur.archlinux.org/cgit/aur.git/plain/010-lcevcdec-fix-pkgconfig-libs.patch?h=lcevcdec&id=a3470fad7d64dfc9d5ebd7ed0c09cb1fb5e2488f";
      hash = "sha256-z65W3k2OA/QDX0jJu4nmXtpi8kTcUFN7cK82PsI4jrQ=";
    })
  ];

  postPatch = ''
    substituteInPlace cmake/tools/version_files.py \
      --replace-fail "args.git_version" '"${finalAttrs.version}"' \
      --replace-fail "args.git_hash" '"${finalAttrs.src.rev}"' \
      --replace-fail "args.git_date" '"1970-01-01"'
    substituteInPlace cmake/templates/lcevc_dec.pc.in \
      --replace-fail "@GIT_SHORT_VERSION@" "${finalAttrs.version}"

  ''
  + lib.optionalString (!stdenv.hostPlatform.avxSupport) ''
    substituteInPlace cmake/modules/Compiler/GNU.cmake \
      --replace-fail "-mavx" ""

     substituteInPlace src/core/decoder/src/common/simd.c \
      --replace-fail "((_xgetbv(kControlRegister) & kOSXSaveMask) == kOSXSaveMask)" "false"
  '';

  env = {
    includedir = "${placeholder "dev"}/include";
    libdir = "${placeholder "out"}/lib";
    NIX_CFLAGS_COMPILE = "-Wno-error=unused-variable";
  };

  nativeBuildInputs = [
    cmake
    git
    pkg-config
    python3
  ];

  buildInputs = [
    nlohmann_json
  ];

  cmakeFlags = [
    (lib.cmakeFeature "VN_SDK_FFMPEG_LIBS_PACKAGE" "")
    (lib.cmakeBool "VN_SDK_UNIT_TESTS" false)
    (lib.cmakeBool "VN_SDK_SAMPLE_SOURCE" false)
    (lib.cmakeBool "VN_SDK_JSON_CONFIG" true)
    (lib.cmakeBool "VN_CORE_AVX2" stdenv.hostPlatform.avx2Support)
    # Requires avx for checking on runtime
    (lib.cmakeBool "VN_CORE_SSE" stdenv.hostPlatform.avxSupport)
  ];

  passthru = {
    updateScript = gitUpdater { };
    tests.pkg-config = testers.testMetaPkgConfig finalAttrs.finalPackage;
  };

  meta = {
    homepage = "https://github.com/v-novaltd/LCEVCdec";
    description = "MPEG-5 LCEVC Decoder";
    license = lib.licenses.bsd3Clear;
    pkgConfigModules = [ "lcevc_dec" ];
    maintainers = with lib.maintainers; [ jopejoe1 ];
    # https://github.com/v-novaltd/LCEVCdec/blob/bf7e0d91c969502e90a925942510a1ca8088afec/cmake/modules/VNovaProject.cmake#L29
    platforms = lib.platforms.aarch ++ lib.platforms.x86;
  };
})
