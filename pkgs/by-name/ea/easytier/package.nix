{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  protobuf,
  pkg-config,
  openssl,
  nixosTests,
  nix-update-script,
  installShellFiles,
  mold,
  withQuic ? false, # with QUIC protocol support

  formats,
  bash,
  iproute2,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "easytier";
  version = "2.6.4";

  src = fetchFromGitHub {
    owner = "EasyTier";
    repo = "EasyTier";
    tag = "v${finalAttrs.version}";
    hash = "sha256-lwqpOVKFm85AiBb7NWLAkjSrWSe5pzF0AuEmmDo+v0k=";
  };

  cargoPatches = [
    # TODO: remove this patch once upstream bumps webpki
    #  webpki-roots 0.26.3 -> 0.26.11
    #  rustls-webpki 0.103.3 -> 0.103.16
    #  webpki-roots 1.0.6 -> 1.0.10
    ./bump-webpki.patch
  ];

  cargoHash = "sha256-IxdKZABnBBCr4+n+5rYLK81D2ULuSvfv31DSN/JHJZQ=";

  nativeBuildInputs = [
    protobuf
    pkg-config
    rustPlatform.bindgenHook
    installShellFiles
    mold
  ];

  buildInputs = [ openssl ];

  buildNoDefaultFeatures = stdenv.hostPlatform.isMips;
  buildFeatures = lib.optional stdenv.hostPlatform.isMips "mips" ++ lib.optional withQuic "quic";

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd easytier-cli \
      --bash <($out/bin/easytier-cli gen-autocomplete bash) \
      --fish <($out/bin/easytier-cli gen-autocomplete fish) \
      --zsh <($out/bin/easytier-cli gen-autocomplete zsh)
    installShellCompletion --cmd easytier-core \
      --bash <($out/bin/easytier-core --gen-autocomplete bash) \
      --fish <($out/bin/easytier-core --gen-autocomplete fish) \
      --zsh <($out/bin/easytier-core --gen-autocomplete zsh)
  '';

  doCheck = false; # tests failed due to heavy rely on network

  passthru = {
    tests = { inherit (nixosTests) easytier easytier-modular; };
    updateScript = nix-update-script { };
  };

  passthru.services.default = {
    imports = [
      (lib.modules.importApply ./service.nix { inherit formats bash iproute2; })
    ];
    easytier.package = finalAttrs.finalPackage;
  };

  meta = {
    homepage = "https://github.com/EasyTier/EasyTier";
    changelog = "https://github.com/EasyTier/EasyTier/releases/tag/v${finalAttrs.version}";
    description = "Simple, decentralized mesh VPN with WireGuard support";
    longDescription = ''
      EasyTier is a simple, safe and decentralized VPN networking solution implemented
      with the Rust language and Tokio framework.
    '';
    mainProgram = "easytier-core";
    license = lib.licenses.asl20;
    platforms = with lib.platforms; unix ++ windows;
    maintainers = with lib.maintainers; [ ltrump ];
  };
})
