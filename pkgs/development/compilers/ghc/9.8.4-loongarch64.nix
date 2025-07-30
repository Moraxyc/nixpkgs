fetchpatch:
import ./common-hadrian.nix {
  version = "9.8.4";
  sha256 = "17e8188f3c8a5c2f73fb4e35d01032e8dc258835ec876d52c8ad8ee3d24b2fc5";
  extraPatches = [
    (fetchpatch {
      name = "make-interface-files-and-object-files-depend-on-inplace-conf-file.patch";
      url = "https://gitlab.haskell.org/ghc/ghc/-/commit/702f7964373d9ffb1d550ee714bd723d8bb0c1a3.patch";
      sha256 = "sha256-yhX+8OA/5azT+qKlXJX2j7+tT1f1yHg2TDN1rZyxqfk=";
    })
    ./0001-llvmGen-Adapt-to-LLVM-new-pass-manager.patch
    ./0002-configure-Bump-max-LLVM-version-to-19.patch
    ./0003-hadrian-Enable-GHCi-on-all-platforms.patch
  ];
}
