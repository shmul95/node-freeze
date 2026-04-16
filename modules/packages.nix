{ ... }:
{
  perSystem = { pkgs, ... }:
    let
      freezeImpl = pkgs.writeShellApplication {
        name = "node-freeze";

        runtimeInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.curl
          pkgs.gawk
          pkgs.gnugrep
          pkgs.nix
        ];

        text = ''
          set -euo pipefail

          outDir="."
          mode="current"
          explicitVersion=""

          usage() {
            cat <<'EOF'
          usage:
            node-freeze
            node-freeze 24.15.0
            node-freeze --from-nvmrc
            node-freeze --path modules
            node-freeze --from-nvmrc --path modules

          behavior:
            no args           freeze the currently active Node version from `node -v`
            <version>         freeze an explicit version like 24.15.0
            --from-nvmrc      freeze the version declared in .nvmrc
            --path <dir>      write <dir>/.node-source.nix instead of ./.node-source.nix
          EOF
          }

          trim_space() {
            awk '{$1=$1; print}'
          }

          normalize_version() {
            local raw="$1"
            raw="$(printf '%s' "$raw" | trim_space)"
            raw="''${raw#v}"
            printf '%s' "$raw"
          }

          validate_version() {
            local v="$1"
            if ! printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
              echo "error: version must be a concrete semver like 24.15.0, got: $v" >&2
              exit 1
            fi
          }

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --from-nvmrc)
                mode="nvmrc"
                shift
                ;;
              --path)
                if [ "$#" -lt 2 ]; then
                  echo "error: --path requires a directory argument" >&2
                  exit 1
                fi
                outDir="$2"
                shift 2
                ;;
              --help|-h)
                usage
                exit 0
                ;;
              -*)
                echo "error: unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
              *)
                if [ -n "$explicitVersion" ]; then
                  echo "error: only one explicit version may be provided" >&2
                  exit 1
                fi
                explicitVersion="$1"
                mode="explicit"
                shift
                ;;
            esac
          done

          case "$mode" in
            explicit)
              version="$(normalize_version "$explicitVersion")"
              ;;
            nvmrc)
              if [ ! -f .nvmrc ]; then
                echo "error: .nvmrc not found in the current directory" >&2
                exit 1
              fi
              version="$(normalize_version "$(cat .nvmrc)")"
              ;;
            current)
              if ! command -v node >/dev/null 2>&1; then
                echo "error: node is not available in PATH; activate Node first or pass an explicit version" >&2
                exit 1
              fi
              version="$(normalize_version "$(node -v)")"
              ;;
            *)
              echo "error: internal mode failure: $mode" >&2
              exit 1
              ;;
          esac

          validate_version "$version"

          case "$(uname -s)-$(uname -m)" in
            Linux-x86_64)
              archive="node-v''${version}-linux-x64.tar.xz"
              ;;
            Linux-aarch64)
              archive="node-v''${version}-linux-arm64.tar.xz"
              ;;
            Darwin-x86_64)
              archive="node-v''${version}-darwin-x64.tar.gz"
              ;;
            Darwin-arm64)
              archive="node-v''${version}-darwin-arm64.tar.gz"
              ;;
            *)
              echo "error: unsupported platform: $(uname -s)-$(uname -m)" >&2
              exit 1
              ;;
          esac

          shasumsUrl="https://nodejs.org/dist/v''${version}/SHASUMS256.txt"

          hexHash="$(
            curl -fsSL "$shasumsUrl" \
              | grep "  ''${archive}$" \
              | awk '{print $1}'
          )"

          if [ -z "$hexHash" ]; then
            echo "error: could not find checksum for $archive in $shasumsUrl" >&2
            exit 1
          fi

          sriHash="$(printf '%s' "$hexHash" | nix hash convert --hash-algo sha256 --to sri)"

          mkdir -p "$outDir"
          outFile="$outDir/.node-source.nix"

          cat > "$outFile" <<EOF
          {
            version = "$version";
            sha256 = "$sriHash";
          }
          EOF

          echo "wrote $outFile"
          echo "version: $version"
          echo "archive: $archive"
          echo "sha256: $sriHash"
        '';
      };

      aliasPkg = pkgs.runCommand "nvm-freeze-alias" { } ''
        mkdir -p "$out/bin"
        ln -s "${freezeImpl}/bin/node-freeze" "$out/bin/nvm-freeze"
      '';

      freezeCli = pkgs.symlinkJoin {
        name = "freeze-cli";
        paths = [
          freezeImpl
          aliasPkg
        ];

        meta = {
          description = "Freeze a Node version into .node-source.nix under both node-freeze and nvm-freeze names";
          mainProgram = "node-freeze";
        };
      };
    in
    {
      packages = {
        default = freezeCli;
        freeze-cli = freezeCli;
      };
    };
}
