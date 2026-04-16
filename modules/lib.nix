{ ... }:
{
  flake.lib.mkFreezedNode = pkgs: sourceFile:
    (pkgs.callPackage
      ({ stdenvNoCC, fetchurl, xz, gnutar }:
        sourceFile:

        let
          source = import sourceFile;

          hostSystem = stdenvNoCC.hostPlatform.system;

          nodePlatform =
            if hostSystem == "x86_64-linux" then "linux-x64"
            else if hostSystem == "aarch64-linux" then "linux-arm64"
            else if hostSystem == "x86_64-darwin" then "darwin-x64"
            else if hostSystem == "aarch64-darwin" then "darwin-arm64"
            else throw "Unsupported system: ${hostSystem}";

          archive =
            if stdenvNoCC.hostPlatform.isDarwin
            then "node-v${source.version}-${nodePlatform}.tar.gz"
            else "node-v${source.version}-${nodePlatform}.tar.xz";
        in
        stdenvNoCC.mkDerivation {
          pname = "nodejs-upstream";
          version = source.version;

          src = fetchurl {
            url = "https://nodejs.org/dist/v${source.version}/${archive}";
            sha256 = source.sha256;
          };

          nativeBuildInputs = [
            xz
            gnutar
          ];

          sourceRoot = ".";

          unpackPhase = ''
            runHook preUnpack
            mkdir source
            cd source
            tar -xf "$src" --strip-components=1
            runHook postUnpack
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p "$out"
            cp -R ./* "$out/"
            runHook postInstall
          '';

          meta = {
            description = "Official upstream Node.js binary pinned by .node-source.nix";
            platforms = [
              "x86_64-linux"
              "aarch64-linux"
              "x86_64-darwin"
              "aarch64-darwin"
            ];
          };
        })
      { })
    sourceFile;
}
