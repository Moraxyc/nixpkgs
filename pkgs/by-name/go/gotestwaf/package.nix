{
  lib,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGoModule rec {
  pname = "gotestwaf";
  version = "0.5.6";

  src = fetchFromGitHub {
    owner = "wallarm";
    repo = "gotestwaf";
    tag = "v${version}";
    hash = "sha256-bZ8cNREPUgIO7lJg0WBtc9qvkDUnfqtFNi612Ctcxo8=";
  };

  vendorHash = "sha256-mPqCphweDF9RQibdjTaXXfXdO8NENHVMdIPxrJEw2g4=";

  nativeInstallCheckInputs = [ versionCheckHook ];

  ldflags = [
    "-w"
    "-s"
    "-X=github.com/wallarm/gotestwaf/internal/version.Version=v${version}"
  ];

  # Tests require network access
  doCheck = false;

  doInstallCheck = true;

  versionCheckProgramArg = "--version";

  meta = {
    description = "Tool for API and OWASP attack simulation";
    homepage = "https://github.com/wallarm/gotestwaf";
    changelog = "https://github.com/wallarm/gotestwaf/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ fab ];
    mainProgram = "gotestwaf";
  };
}
