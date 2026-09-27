{
  lib,
  rustPlatform,
}:
let
  inherit (lib.importTOML ./Cargo.toml) package;
in
rustPlatform.buildRustPackage {
  pname = package.name;
  inherit (package) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.lock
      ./Cargo.toml
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Generator for the static bits of /etc for NixOS (internal use)";
    mainProgram = package.name;
    maintainers = with lib.maintainers; [ ];
    license = with lib.licenses; [ mit ];
  };
}
