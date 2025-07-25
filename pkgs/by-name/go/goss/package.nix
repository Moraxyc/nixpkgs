{
  bash,
  buildGoModule,
  fetchFromGitHub,
  getent,
  goss,
  lib,
  makeWrapper,
  nix-update-script,
  nixosTests,
  stdenv,
  systemd,
  testers,
}:

buildGoModule rec {
  pname = "goss";
  version = "0.4.9";

  src = fetchFromGitHub {
    owner = "goss-org";
    repo = "goss";
    tag = "v${version}";
    hash = "sha256-GdkLasokpWegjK4kZzAskp1NGwcuMjrjjau75cEo8kg=";
  };

  vendorHash = "sha256-Rf6Xt54y1BN2o90rDW0WvEm4H5pPfsZ786MXFjsAFaM=";

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X github.com/goss-org/goss/util.Version=v${version}"
  ];

  nativeBuildInputs = [ makeWrapper ];

  postInstall =
    let
      runtimeDependencies = [
        bash
        getent
      ]
      ++ lib.optionals stdenv.hostPlatform.isLinux [ systemd ];
    in
    ''
      wrapProgram $out/bin/goss \
        --prefix PATH : "${lib.makeBinPath runtimeDependencies}"
    '';

  passthru = {
    tests = {
      inherit (nixosTests) goss;
      version = testers.testVersion {
        command = "goss --version";
        package = goss;
        version = "v${version}";
      };
    };
    updateScript = nix-update-script { };
  };

  meta = {
    homepage = "https://github.com/goss-org/goss/";
    changelog = "https://github.com/goss-org/goss/releases/tag/v${version}";
    description = "Quick and easy server validation";
    longDescription = ''
      Goss is a YAML based serverspec alternative tool for validating a server’s configuration.
      It eases the process of writing tests by allowing the user to generate tests from the current system state.
      Once the test suite is written they can be executed, waited-on, or served as a health endpoint.
    '';
    license = lib.licenses.asl20;
    mainProgram = "goss";
    maintainers = with lib.maintainers; [
      hyzual
      jk
      anthonyroussel
    ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
