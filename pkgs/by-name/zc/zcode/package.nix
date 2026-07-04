{
  lib,
  stdenv,
  fetchurl,

  autoPatchelfHook,
  dpkg,
  makeBinaryWrapper,
  wrapGAppsHook3,
  undmg,

  alsa-lib,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libgbm,
  libGL,
  libxkbcommon,
  nspr,
  nss,
  pango,
  udev,
  vulkan-loader,
  wayland,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,

  ripgrep,
}:

let
  inherit (stdenv.hostPlatform) system isLinux isDarwin;
  archiveExt = if isDarwin then "dmg" else "deb";
  platform = if isDarwin then "mac" else "linux";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zcode";
  version = "3.2.2";

  src = fetchurl {
    url = "https://cdn-zcode.z.ai/zcode/electron/releases/${finalAttrs.version}/ZCode-${finalAttrs.version}-${platform}-${stdenv.hostPlatform.node.arch}.${archiveExt}";
    hash = finalAttrs.passthru.srcHashes.${system} or (throw "Unsupported system: ${system}");
  };

  strictDeps = true;
  __structuredAttrs = true;

  sourceRoot = lib.optionalString isDarwin ".";

  nativeBuildInputs = [
    makeBinaryWrapper
  ]
  ++ lib.optionals isLinux [
    autoPatchelfHook
    dpkg
    wrapGAppsHook3
  ]
  ++ lib.optionals isDarwin [
    undmg
  ];

  buildInputs = lib.optionals isLinux [
    stdenv.cc.cc.lib

    alsa-lib
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libgbm
    libGL
    libxkbcommon
    nspr
    nss
    pango
    udev
    vulkan-loader
    wayland
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  dontWrapGApps = isLinux;

  installPhase = ''
    runHook preInstall
  ''
  + lib.optionalString isLinux ''
    mkdir -p "$out"/{bin,opt,share/{applications,icons,licenses/zcode}}

    rm -f opt/ZCode/resources/app-update.yml
    rm -f opt/ZCode/chrome-sandbox
    rm -rf opt/ZCode/resources/{apparmor-profile,package-type}
    rm -rf \
      opt/ZCode/resources/app.asar.unpacked/node_modules/node-pty/prebuilds/darwin-* \
      opt/ZCode/resources/app.asar.unpacked/node_modules/node-pty/prebuilds/win32-* \
      opt/ZCode/resources/app.asar.unpacked/node_modules/node-pty/deps/winpty \
      opt/ZCode/resources/app.asar.unpacked/node_modules/node-pty/src \
      opt/ZCode/resources/app.asar.unpacked/node_modules/node-pty/scripts

    rm -f opt/ZCode/resources/tools/ripgrep/rg
    ln -sf "${lib.getExe ripgrep}" opt/ZCode/resources/tools/ripgrep/rg

    mv opt/ZCode/LICENSE* $out/share/licenses/zcode/

    cp -a usr/share/icons $out/share/

    cp -a opt/ZCode $out/opt/
    chmod -R u+w $out/opt/ZCode

    substitute usr/share/applications/zcode.desktop "$out/share/applications/zcode.desktop" \
      --replace-fail "/opt/ZCode/zcode" "zcode"

    makeWrapper "$out/opt/ZCode/zcode" "$out/bin/zcode" \
      "''${gappsWrapperArgs[@]}" \
      --suffix LD_LIBRARY_PATH : /run/opengl-driver/lib \
      --add-flags "--no-sandbox" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-wayland-ime=true --wayland-text-input-version=3}}"
  ''
  + lib.optionalString isDarwin ''
    mkdir -p "$out/Applications" "$out/bin"

    cp -a "ZCode.app" "$out/Applications/"

    makeWrapper \
      "$out/Applications/ZCode.app/Contents/MacOS/ZCode" \
      "$out/bin/zcode"
  ''
  + ''
    runHook postInstall
  '';

  preFixup = lib.optionalString isLinux ''
    addAutoPatchelfSearchPath $out/opt/ZCode
    addAutoPatchelfSearchPath $out/opt/ZCode/resources/app.asar.unpacked
    patchelf \
      --add-needed "${libGL}/lib/libEGL.so.1" \
      --add-needed "${vulkan-loader}/lib/libvulkan.so.1" \
      "$out/opt/ZCode/zcode"
  '';

  passthru = {
    srcHashes = {
      x86_64-linux = "sha256-wtBujy2bUoeTBOmfhmN+kuewIovuaf1bDDFq6R3cmPI=";
      aarch64-linux = lib.fakeHash;
      x86_64-darwin = lib.fakeHash;
      aarch64-darwin = "sha256-6qK91d55QhcG4ZGGiRdHfGzcrVZ311gk+/zFf3Fhxik=";
    };
  };

  meta = {
    description = "Agentic Development Environment built to bring GLM-5.2 into real coding workflows";
    homepage = "https://zcode.z.ai";
    downloadPage = "https://zcode.z.ai/#all-downloads";
    changelog = "https://zcode.z.ai/changelog";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames finalAttrs.passthru.srcHashes;
    maintainers = with lib.maintainers; [ moraxyc ];
    mainProgram = "zcode";
  };
})
