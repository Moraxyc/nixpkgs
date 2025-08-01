{
  lib,
  aiohttp,
  buildPythonPackage,
  fetchFromGitHub,
  loguru,
  numpy,
  setuptools,
  unasync,
  urllib3,
}:

buildPythonPackage rec {
  pname = "pyosohotwaterapi";
  version = "1.2.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "osohotwateriot";
    repo = "apyosohotwaterapi";
    tag = version;
    hash = "sha256-GFjA1RtJC2bxSoH2TIZwEdSAvpteYBTbsS81hhp4Y3E=";
  };

  build-system = [
    setuptools
    unasync
  ];

  dependencies = [
    aiohttp
    loguru
    numpy
    urllib3
  ];

  preBuild = ''
    export HOME=$(mktemp -d)
  '';

  # Module has no tests
  doCheck = false;

  pythonImportsCheck = [ "apyosoenergyapi" ];

  meta = with lib; {
    description = "Module for using the OSO Hotwater API";
    homepage = "https://github.com/osohotwateriot/apyosohotwaterapi";
    changelog = "https://github.com/osohotwateriot/apyosohotwaterapi/releases/tag/${src.tag}";
    license = licenses.mit;
    maintainers = with maintainers; [ fab ];
  };
}
