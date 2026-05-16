{
  lib,
  stdenvNoCC,
  callPackage,
  ...
}@args:

let
  extraArgs = removeAttrs args [ "callPackage" ];

  sources = lib.importJSON ./sources.json;
  srcInfo =
    sources.${stdenvNoCC.hostPlatform.system}
      or sources.${lib.optionalString stdenvNoCC.hostPlatform.isDarwin "any-darwin"}
      or (throw "Unsupported platform: ${stdenvNoCC.hostPlatform.system}");

  passthru = {
    updateScript = ./update.sh;
  };

  meta = {
    maintainers = with lib.maintainers; [ xddxdd ];
    description = "Tencent QQ Music";
    homepage = "https://y.qq.com/";
    platforms = lib.remove "any-darwin" (lib.attrNames sources) ++ lib.platforms.darwin;
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "qqmusic";
  };
in
if stdenvNoCC.hostPlatform.isDarwin then
  callPackage ./darwin.nix (extraArgs // { inherit meta passthru srcInfo; })
else
  callPackage ./linux.nix (extraArgs // { inherit meta passthru srcInfo; })
