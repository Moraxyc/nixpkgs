{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pytestCheckHook,
  pythonOlder,
}:

buildPythonPackage rec {
  pname = "pybase64";
  version = "1.4.0";
  format = "setuptools";

  disabled = pythonOlder "3.6";

  src = fetchFromGitHub {
    owner = "mayeut";
    repo = "pybase64";
    rev = "refs/tags/v${version}";
    hash = "sha256-Yl0P9Ygy6IirjSFrutl+fmn4BnUL1nXzbQgADNQFg3I=";
    fetchSubmodules = true;
  };

  nativeCheckInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "pybase64" ];

  meta = with lib; {
    description = "Fast Base64 encoding/decoding";
    mainProgram = "pybase64";
    homepage = "https://github.com/mayeut/pybase64";
    changelog = "https://github.com/mayeut/pybase64/releases/tag/v${version}";
    license = licenses.bsd2;
    maintainers = [ ];
  };
}
