{
  description = "Mole - Deep clean and optimize your Mac";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-darwin" "aarch64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        version = "1.30.0";

        archSuffix = if system == "aarch64-darwin" then "arm64" else "amd64";

        # Prebuilt Go binaries from GitHub releases
        analyzeBin = pkgs.fetchurl {
          url = "https://github.com/tw93/Mole/releases/download/V${version}/analyze-darwin-${archSuffix}";
          sha256 = if archSuffix == "arm64"
            then "sha256-jktoZmP5Kv04z3+HqXeHrYm0ZIkpH3+NxusZNly7YfA="
            else "sha256-7ve81TtA08vBy8pXbVEaTuR9MPFvSj7yfJcHWYfq+lo=";
        };

        statusBin = pkgs.fetchurl {
          url = "https://github.com/tw93/Mole/releases/download/V${version}/status-darwin-${archSuffix}";
          sha256 = if archSuffix == "arm64"
            then "sha256-owoPwOigBTBiC6Jzp/ex312rnEE/kdZY8OEhNKZu+U8="
            else "sha256-+uy6EKVvX4BGD3KbAMLNcbVJBBPUHnUoqXy/nu65h/o=";
        };

        runtimeDeps = with pkgs; [ bash coreutils curl gnugrep gnused ];

        # Shared install logic for both variants
        mkMole = { goBinaries }:
          pkgs.stdenv.mkDerivation {
            pname = "mole";
            inherit version;
            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];

            dontBuild = true;

            installPhase = ''
              runHook preInstall

              # Set up the SCRIPT_DIR layout expected by mole
              mkdir -p $out/share/mole/bin $out/share/mole/lib $out/bin

              # Install shell libraries
              cp -r lib/* $out/share/mole/lib/

              # Install bin/ shell scripts (subcommand entry points)
              cp bin/*.sh $out/share/mole/bin/
              chmod +x $out/share/mole/bin/*.sh

              # Install Go binaries
              install -m755 ${goBinaries.analyze} $out/share/mole/bin/analyze-go
              install -m755 ${goBinaries.status} $out/share/mole/bin/status-go

              # Install main script with SCRIPT_DIR patched
              substitute mole $out/share/mole/mole \
                --replace-fail 'SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"' \
                               'SCRIPT_DIR="'"$out"'/share/mole"'
              chmod +x $out/share/mole/mole

              # Install mo alias with patched path
              substitute mo $out/share/mole/mo \
                --replace-fail 'SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"' \
                               'SCRIPT_DIR="'"$out"'/share/mole"'
              chmod +x $out/share/mole/mo

              # Create wrapped executables in $out/bin
              # --run ensures the log directory exists before mole runs
              makeWrapper $out/share/mole/mole $out/bin/mole \
                --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
                --run 'mkdir -p "$HOME/Library/Logs/mole"'

              makeWrapper $out/share/mole/mo $out/bin/mo \
                --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
                --run 'mkdir -p "$HOME/Library/Logs/mole"'

              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Deep clean and optimize your Mac";
              homepage = "https://github.com/tw93/Mole";
              license = licenses.mit;
              platforms = [ "x86_64-darwin" "aarch64-darwin" ];
              mainProgram = "mole";
            };
          };

        # Go binaries built from source
        goBinariesFromSource =
          let
            goMod = pkgs.buildGoModule {
              pname = "mole-go";
              inherit version;
              src = ./.;
              vendorHash = "sha256-LznLZ0NO8VBWP95ReAVORUMIDhh7/pgTY5mGNN2tND8=";
              ldflags = [ "-s" "-w" ];
              subPackages = [ "cmd/analyze" "cmd/status" ];
            };
          in {
            analyze = "${goMod}/bin/analyze";
            status = "${goMod}/bin/status";
          };

      in {
        packages = {
          # Default: uses prebuilt binaries from GitHub releases
          default = mkMole {
            goBinaries = {
              analyze = analyzeBin;
              status = statusBin;
            };
          };

          # Build Go components from source
          from-source = mkMole {
            goBinaries = goBinariesFromSource;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ go bash shellcheck bats ];
        };
      }
    );
}
