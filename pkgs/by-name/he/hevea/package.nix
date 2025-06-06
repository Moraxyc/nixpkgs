{
  lib,
  stdenv,
  fetchurl,
  ocamlPackages,
}:

stdenv.mkDerivation rec {
  pname = "hevea";
  version = "2.36";

  src = fetchurl {
    url = "https://hevea.inria.fr/distri/hevea-${version}.tar.gz";
    sha256 = "sha256-XWdZ13AqKVx2oSwbKhoWdUqw7B/+1z/J0LE4tB5yBkg=";
  };

  strictDeps = true;

  nativeBuildInputs = with ocamlPackages; [
    ocaml
    ocamlbuild
  ];

  makeFlags = [ "PREFIX=$(out)" ];

  meta = {
    description = "Quite complete and fast LATEX to HTML translator";
    homepage = "https://hevea.inria.fr/";
    changelog = "https://github.com/maranget/hevea/raw/v${version}/CHANGES";
    license = lib.licenses.qpl;
    maintainers = with lib.maintainers; [ pSub ];
    platforms = with lib.platforms; unix;
  };
}
