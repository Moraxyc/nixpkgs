{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  setuptools-scm,
  altair,
  fastapi,
  geopandas,
  kaleido,
  llmx,
  matplotlib,
  matplotlib-venn,
  networkx,
  numpy,
  pandas,
  plotly,
  plotnine,
  pydantic,
  python-multipart,
  scipy,
  seaborn,
  statsmodels,
  typer,
  uvicorn,
  wordcloud,
  peacasso,
  basemap,
  basemap-data-hires,
  geopy,
  python,
}:

buildPythonPackage rec {
  pname = "lida";
  version = "0-unstable-2024-03-03";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "lida";
    rev = "d892e20be0cf8263644f2575f097ccecebebf812";
    hash = "sha256-OLhA4M5C9yyxb3eJ9Fge5HEDINS7BHaDmhsYFXF9+rU=";
  };

  patches = [
    # The upstream places the data path under the py file's own directory.
    # However, since `/nix/store` is read-only, we patch it to the user's home directory.
    ./rw_data.patch
  ];

  build-system = [
    setuptools
    setuptools-scm
  ];

  dependencies = [
    altair
    fastapi
    geopandas
    kaleido
    llmx
    matplotlib
    matplotlib-venn
    networkx
    numpy
    pandas
    plotly
    plotnine
    pydantic
    python-multipart
    scipy
    seaborn
    statsmodels
    typer
    uvicorn
    wordcloud
  ];

  optional-dependencies = {
    infographics = [
      peacasso
    ];
    tools = [
      basemap
      basemap-data-hires
      geopy
    ];
    transformers = [
      llmx
    ];
    web = [
      fastapi
      uvicorn
    ];
  };

  # require network
  doCheck = false;

  pythonImportsCheck = [ "lida" ];

  meta = {
    description = "Automatic Generation of Visualizations and Infographics using Large Language Models";
    homepage = "https://github.com/microsoft/lida";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ moraxyc ];
    mainProgram = "lida";
  };
}
