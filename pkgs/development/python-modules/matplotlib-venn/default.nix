{
  lib,
  fetchPypi,
  buildPythonPackage,
  setuptools,
  python3Packages,
}:

buildPythonPackage rec {
  version = "0.11.10";
  pname = "matplotlib-venn";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-kNDPsnnF273339ciwOJRWjf1NelJvK0XRIO8d343LmU=";
  };

  build-system = [ setuptools ];

  dependencies = with python3Packages; [
    matplotlib
    numpy
    scipy
  ];

  nativeCheckInputs = with python3Packages; [ pytestCheckHook ];

  meta = with lib; {
    description = "Functions for plotting area-proportional two- and three-way Venn diagrams in matplotlib";
    homepage = "https://github.com/konstantint/matplotlib-venn";
    license = licenses.mit;
    maintainers = with maintainers; [ moraxyc ];
  };
}
