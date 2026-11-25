{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  hatch-vcs,
  hatchling,
  pytest-asyncio,
  pytest-mock,
  pytest-timeout,
  pytestCheckHook,
  stdenv,
}:

buildPythonPackage (finalAttrs: {
  pname = "filelock";
  version = "4.2.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "tox-dev";
    repo = "filelock";
    tag = finalAttrs.version;
    hash = "sha256-oN4nr4p/vPpg5620LEpqYILofYl2rpaPN5lJqySR6ZE=";
  };

  build-system = [
    hatch-vcs
    hatchling
  ];

  nativeCheckInputs = [
    pytest-asyncio
    pytest-mock
    pytest-timeout
    pytestCheckHook
  ];

  pythonImportsCheck = [ "filelock" ];

  disabledTestPaths = [
    # Circular dependency with virtualenv
    "tests/test_virtualenv.py"
    # Very prone to timeouts on busy machines
    "tests/test_filelock.py"
    "tests/test_read_write.py"
  ];

  disabledTests = lib.optionals stdenv.hostPlatform.isLinux [
    # Creates a claim file after the claim directory fd is opened and expects
    # scandir(dir_fd) to observe it; POSIX leaves visibility unspecified and
    # Linux 6.6+ tmpfs omits entries added after opendir().
    "test_strict_soft_doorway_preserves_every_claim_cleanup_error"
  ];

  doCheck = !stdenv.hostPlatform.isFreeBSD;

  meta = {
    changelog = "https://github.com/tox-dev/filelock/blob/${finalAttrs.src.tag}/docs/changelog.rst";
    description = "Platform independent file lock for Python";
    homepage = "https://github.com/benediktschmitt/py-filelock";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
})
