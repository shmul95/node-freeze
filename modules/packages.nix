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
          pkgs.jq
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

          shasumsUrl="https://nodejs.org/dist/v''${version}/SHASUMS256.txt"
          shasums="$(curl -fsSL "$shasumsUrl")"

          archive_for_system() {
            case "$1" in
              x86_64-linux)
                printf '%s' "node-v''${version}-linux-x64.tar.xz"
                ;;
              aarch64-linux)
                printf '%s' "node-v''${version}-linux-arm64.tar.xz"
                ;;
              x86_64-darwin)
                printf '%s' "node-v''${version}-darwin-x64.tar.gz"
                ;;
              aarch64-darwin)
                printf '%s' "node-v''${version}-darwin-arm64.tar.gz"
                ;;
              *)
                echo "error: unsupported system: $1" >&2
                exit 1
                ;;
            esac
          }

          hash_for_system() {
            local system="$1"
            local archive
            local hexHash

            archive="$(archive_for_system "$system")"
            hexHash="$(
              printf '%s\n' "$shasums" \
                | grep "  ''${archive}$" \
                | awk '{print $1}'
            )"

            if [ -z "$hexHash" ]; then
              echo "error: could not find checksum for $archive in $shasumsUrl" >&2
              exit 1
            fi

            nix hash convert --hash-algo sha256 --to sri "$hexHash"
          }

          x86_64_linux_hash="$(hash_for_system x86_64-linux)"
          aarch64_linux_hash="$(hash_for_system aarch64-linux)"
          x86_64_darwin_hash="$(hash_for_system x86_64-darwin)"
          aarch64_darwin_hash="$(hash_for_system aarch64-darwin)"

          mkdir -p "$outDir"
          outFile="$outDir/.node-source.nix"

          cat > "$outFile" <<EOF
          {
            version = "$version";
            hashes = {
              "x86_64-linux" = "$x86_64_linux_hash";
              "aarch64-linux" = "$aarch64_linux_hash";
              "x86_64-darwin" = "$x86_64_darwin_hash";
              "aarch64-darwin" = "$aarch64_darwin_hash";
            };
          }
          EOF

          echo "wrote $outFile"
          echo "version: $version"
          echo "x86_64-linux: $x86_64_linux_hash"
          echo "aarch64-linux: $aarch64_linux_hash"
          echo "x86_64-darwin: $x86_64_darwin_hash"
          echo "aarch64-darwin: $aarch64_darwin_hash"
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
