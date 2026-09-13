{
  lib,
  stdenvNoCC,
  bun-bin,
}:

{
  version,
  src,
  hash,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "bun-node-modules";
  inherit version src;

  strictDeps = true;
  nativeBuildInputs = [
    bun-bin
  ];
  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
    mkdir -p "$HOME" "$BUN_INSTALL_CACHE_DIR"

    for packageDir in . packages/bun-error src/node-fallbacks; do
      (
        cd "$packageDir"
        bun install --frozen-lockfile --omit=optional
      )
    done

    # Prune architecture-specific binaries
    rm -rf \
      node_modules/@esbuild \
      node_modules/@oxlint \
      node_modules/.bin/esbuild \
      node_modules/.bin/oxlint

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -R --parents \
      node_modules \
      packages/bun-error/node_modules \
      src/node-fallbacks/node_modules \
      "$out"

    runHook postInstall
  '';

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = hash;
})
