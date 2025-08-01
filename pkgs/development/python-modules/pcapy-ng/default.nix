{
  lib,
  buildPythonPackage,
  cython,
  fetchFromGitHub,
  libpcap,
  pkgconfig,
  pytestCheckHook,
  pythonOlder,
}:

buildPythonPackage rec {
  pname = "pcapy-ng";
  version = "1.0.9";
  format = "setuptools";

  disabled = pythonOlder "3.7";

  src = fetchFromGitHub {
    owner = "stamparm";
    repo = "pcapy-ng";
    rev = version;
    hash = "sha256-6LA2n7Kv0MiZcqUJpi0lDN4Q+GcOttYw7hJwVqK/DU0=";
  };

  nativeBuildInputs = [
    cython
    pkgconfig
  ];

  buildInputs = [ libpcap ];

  nativeCheckInputs = [ pytestCheckHook ];

  preCheck = ''
    cd tests
  '';

  pythonImportsCheck = [ "pcapy" ];

  doCheck = pythonOlder "3.10";

  enabledTestPaths = [ "pcapytests.py" ];

  meta = with lib; {
    description = "Module to interface with the libpcap packet capture library";
    homepage = "https://github.com/stamparm/pcapy-ng/";
    license = licenses.bsd2;
    maintainers = with maintainers; [ fab ];
  };
}
