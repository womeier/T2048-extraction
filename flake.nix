{
  description = "T2048, a verified 2048 game — Rocq library and Wasm web build via CertiRocq";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        lib = nixpkgs.lib;
        pkgs = import nixpkgs {
          inherit system;
          # CertiRocq depends on CompCert (unfree) for its Clight backend.
          config.allowUnfreePredicate =
            pkg: builtins.elem (lib.getName pkg) [ "compcert" ];
        };
        rocqPackages = pkgs.rocqPackages_9_1;

        t2048-rev = "8f8b5020b060bc0876cb16a6b8802a9ab21c1673";

        t2048 = rocqPackages.mkRocqDerivation {
          pname = "T2048";
          version = "dev";
          owner = "thery";
          repo = "T2048";
          src = pkgs.fetchFromGitHub {
            owner = "thery";
            repo = "T2048";
            rev = t2048-rev;
            hash = "sha256-VvrMDv2Kt87c0Udrm3+KGbiSvw8RrjrMqmmyHwy6dwY=";
          };

          useCoq = true;
          namePrefix = [ "coq" ];
          propagatedBuildInputs = [ rocqPackages.stdlib ];

          meta = {
            description = "A version of the 2048 game for Rocq";
            license = lib.licenses.mit;
            homepage = "https://github.com/thery/T2048";
          };
        };

        rocq-with-t2048 = rocqPackages.rocq-core.withPackages (
          ps: [
            ps.stdlib
            t2048
          ]
        );

        # The web bundle: index.html + index.js + the whole game compiled
        # to a single Wasm module by CertiRocq's verified Wasm backend.
        t2048-web = pkgs.stdenv.mkDerivation {
          pname = "t2048-web";
          version = "dev";
          src = lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              type == "directory"
              || lib.hasSuffix ".v" path
              || lib.elem (baseNameOf path) [
                "Makefile"
                "_RocqProject"
                "index.html"
                "index.js"
              ];
          };

          nativeBuildInputs = [
            rocqPackages.coq
            rocqPackages.CertiRocq
          ];
          buildInputs = [ t2048 ];

          COQBIN = "${rocqPackages.coq}/bin/";

          buildPhase = ''
            runHook preBuild
            ulimit -s unlimited 2>/dev/null || true
            make -j $NIX_BUILD_CORES
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp index.html index.js $out/
            cp T2048Web.extraction.T2048_wasm_api.wasm $out/t2048.wasm
            runHook postInstall
          '';

          meta = {
            description = "T2048, a verified 2048 game, compiled to WebAssembly";
            license = lib.licenses.mit;
            homepage = "https://github.com/thery/T2048";
          };
        };
      in
      {
        packages.default = t2048-web;
        packages.t2048-web = t2048-web;
        packages.T2048 = t2048;
        packages.rocq-with-t2048 = rocq-with-t2048;

        devShells.default = pkgs.mkShell {
          name = "T2048";
          packages = [
            rocqPackages.rocq-core
            rocqPackages.coq
            rocqPackages.CertiRocq
            rocqPackages.stdlib
            rocqPackages.coq-lsp
            t2048
            pkgs.gnumake
            pkgs.nodejs_22
          ];

          COQBIN = "${rocqPackages.coq}/bin/";

          shellHook = ''
            echo "T2048 development environment"
            echo "  rocq:  $(rocq --version | head -1)"
            echo "  coq:   $(coqc --version | head -1)"
            echo "  node:  $(node --version)"
            echo ""
            echo "Build the web bundle:  nix build  (or: make)"
            echo "Serve it:              cd result && python3 -m http.server"
          '';
        };
      }
    );
}
