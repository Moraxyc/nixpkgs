{
  lib,
  stdenv,
  symlinkJoin,
  makeBinaryWrapper,
  versionCheckHook,
  bun-unwrapped,
  bun-bin,
}:

let
  inherit (stdenv.hostPlatform) isLinux;
in
symlinkJoin (finalAttrs: {
  pname = "bun";
  inherit (bun-unwrapped) version;

  __structuredAttrs = true;
  strictDeps = true;

  paths = [ bun-unwrapped ];

  disallowedReferences = [ bun-bin ];
  disallowedRequisites = [ bun-bin ];

  nativeBuildInputs = lib.optionals isLinux [ makeBinaryWrapper ];

  postBuild = lib.optionalString isLinux ''
    wrapProgram "$out/bin/bun" \
      --prefix C_INCLUDE_PATH : "${lib.getDev stdenv.cc.libc}/include" \
      --prefix LIBRARY_PATH : "${lib.getLib stdenv.cc.libc}/lib"

    ln -sf bun "$out/bin/bunx"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = {
    unwrapped = bun-unwrapped;
  };

  meta = {
    inherit (bun-unwrapped.meta)
      changelog
      description
      homepage
      license
      longDescription
      mainProgram
      maintainers
      platforms
      ;
    priority = (bun-unwrapped.meta.priority or lib.meta.defaultPriority) - 1;
  };
})
