{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools-scm,
  setuptools,
  python3Packages,
}:

buildPythonPackage rec {
  pname = "llmx";
  version = "0.0.21a0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-OEo6wIaDTktzAsP0rOmhxjFSHygTR/EpcRI6AXsu+6M=";
  };

  disabled = python3Packages.pythonOlder "3.9";

  dependencies = with python3Packages; [
    pydantic
    openai
    tiktoken
    diskcache
    cohere
    google-auth
    typer
    pyyaml
    setuptools
  ];

  build-system = [ setuptools-scm ];

  meta = with lib; {
    description = "LLMX: A library for LLM Text Generation";
    homepage = "https://github.com/victordibia/llmx";
    mainProgram = "llmx";
    license = licenses.mit;
    maintainers = with maintainers; [ moraxyc ];
  };
}
