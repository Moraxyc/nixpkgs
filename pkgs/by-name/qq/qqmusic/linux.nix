{
  fetchurl,
  stdenvNoCC,
  autoPatchelfHook,
  makeWrapper,
  lib,
  makeDesktopItem,
  copyDesktopItems,
  dpkg,
  # QQ Music dependencies
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdbusmenu,
  libglvnd,
  libpulseaudio,
  nspr,
  nss,
  pango,
  pciutils,
  udev,
  libxtst,
  libxscrnsaver,
  libxrender,
  libxrandr,
  libxi,
  libxfixes,
  libxext,
  libxdamage,
  libxcursor,
  libxcomposite,
  libx11,
  libxcb,

  meta,
  passthru,
  srcInfo,
}:
################################################################################
# Mostly based on qqmusic-bin package from AUR:
# https://aur.archlinux.org/packages/qqmusic-bin
################################################################################
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "qqmusic";
  inherit passthru meta;
  inherit (srcInfo) version;

  src = fetchurl rec {
    name = "qqmusic_${srcInfo.version}_amd64.deb";
    url = "https://c.y.qq.com/cgi-bin/file_redirect.fcg?bid=dldir&file=ecosfile_plink%2Fmusic_clntupate%2Flinux%2Fother%2F${name}&sign=${srcInfo.sign}";
    inherit (srcInfo) hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
    dpkg
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdbusmenu
    libglvnd
    libpulseaudio
    nspr
    nss
    pango
    pciutils
    udev
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
  ];

  unpackPhase = ''
    runHook preUnpack

    dpkg -x $src .

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r opt/qqmusic $out/opt
    cp -r usr/* $out/

    rm -rf $out/opt/swiftshader
    ln -sf ${libglvnd}/lib $out/opt/swiftshader

    mkdir -p $out/bin
    makeWrapper $out/opt/qqmusic $out/bin/qqmusic \
      --argv0 "qqmusic" \
      --add-flags "--no-sandbox" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath finalAttrs.buildInputs}"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "qqmusic";
      desktopName = "QQMusic";
      exec = "qqmusic %U";
      terminal = false;
      icon = "qqmusic";
      startupWMClass = "qqmusic";
      comment = "Tencent QQMusic";
      categories = [ "AudioVideo" ];
      extraConfig = {
        "Name[zh_CN]" = "QQ音乐";
        "Name[zh_TW]" = "QQ音樂";
        "Comment[zh_CN]" = "腾讯QQ音乐";
        "Comment[zh_TW]" = "騰訊QQ音樂";
      };
    })
  ];

})
