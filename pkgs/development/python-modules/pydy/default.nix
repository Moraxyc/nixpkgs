{
  lib,
  buildPythonPackage,
  fetchPypi,
  numpy,
  scipy,
  sympy,
  setuptools,
  pynose,
  cython,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "pydy";
  version = "0.7.1";

  pyproject = true;
  build-system = [ setuptools ];

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-aaRinJMGR8v/OVkeSp1hA4+QLOrmDWq50wvA6b/suvk=";
  };

  dependencies = [
    numpy
    scipy
    sympy
  ];

  nativeCheckInputs = [
    pynose
    cython
    pytestCheckHook
  ];

  disabledTests = [
    # wait for upstream to fix
    # https://github.com/pydy/pydy/issues/500
    "test_c_code"
    "test_cython_code"
    "test_scene"
    "test_system"
    "test_ode_function_generator"
  ];

  pythonImportsCheck = [ "pydy" ];

  meta = with lib; {
    description = "Python tool kit for multi-body dynamics";
    homepage = "http://pydy.org";
    license = licenses.bsd3;
    maintainers = [ ];
  };
}
