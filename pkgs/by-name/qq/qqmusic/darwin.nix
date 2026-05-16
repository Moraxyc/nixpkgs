{
  stdenvNoCC,
  fetchurl,
  undmg,

  meta,
  passthru,
  srcInfo,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "qqmusic";
  inherit passthru meta;
  inherit (srcInfo) version;

  src = fetchurl rec {
    name = "QQMusicMac${srcInfo.version}Build${srcInfo.build}.dmg";
    url = "https://c.y.qq.com/cgi-bin/file_redirect.fcg?bid=dldir&file=ecosfile%2Fmusic_clntupate%2Fmac%2Fother%2F${name}&sign=${srcInfo.sign}";
    inherit (srcInfo) hash;
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -r QQMusic.app $out/Applications

    runHook postInstall
  '';
})
