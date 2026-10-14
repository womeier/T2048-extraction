{
  description = "T2048, a verified 2048 game — Rocq library and Wasm web build via CertiRocq";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Nixpkgs 26.11 dropped x86_64-darwin; the 26.05 darwin branch is the
    # last one that carries it (security fixes until the end of 2026).
    # Used for that single system — every other one builds from unstable.
    nixpkgs-x86_64-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-x86_64-darwin,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # Intel macOS builds from the 26.05 darwin branch, the last
        # nixpkgs that supports it; everything else from unstable.
        intelDarwin = system == "x86_64-darwin";
        nixpkgsFor = if intelDarwin then nixpkgs-x86_64-darwin else nixpkgs;

        lib = nixpkgsFor.lib;
        pkgs = import nixpkgsFor {
          inherit system;
          # CertiRocq depends on CompCert (unfree) for its Clight backend.
          config.allowUnfreePredicate =
            pkg: builtins.elem (lib.getName pkg) [ "compcert" ];
        };

        # One Rocq 9.1 toolchain under two sets of attribute names:
        # unstable keeps it all in rocqPackages_9_1, while 26.05 still
        # splits it — the rocq core in rocqPackages_9_1, the Coq-named
        # packages (coqc, CertiRocq, coq-lsp) and the builders in
        # coqPackages_9_1. Both sets are the same rocq 9.1.1 build (they
        # share one stdlib output), so taking each package from the set
        # that carries it is consistent; it is 9.1.1 either way.
        rocqPackages = pkgs.rocqPackages_9_1;
        coqPackages = if intelDarwin then pkgs.coqPackages_9_1 else pkgs.rocqPackages_9_1;
        # the builders and the withPackages wrapper go with those names:
        # mkCoqDerivation/coq.withPackages on 26.05, the rocq-named ones
        # on unstable. Same builder, same resulting coq9.1-T2048-dev.
        mkRocqPackage = if intelDarwin then coqPackages.mkCoqDerivation else rocqPackages.mkRocqDerivation;
        rocqWithPackages =
          if intelDarwin then coqPackages.coq.withPackages else rocqPackages.rocq-core.withPackages;

        t2048-rev = "8f8b5020b060bc0876cb16a6b8802a9ab21c1673";

        t2048 = mkRocqPackage {
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
          propagatedBuildInputs = [ coqPackages.stdlib ];

          meta = {
            description = "A version of the 2048 game for Rocq";
            license = lib.licenses.mit;
            homepage = "https://github.com/thery/T2048";
          };
        };

        rocq-with-t2048 = rocqWithPackages (
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
            coqPackages.coq
            coqPackages.CertiRocq
          ];
          buildInputs = [ t2048 ];

          COQBIN = "${coqPackages.coq}/bin/";

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

        # Every system the flake builds for runs the suite: nixpkgs'
        # Playwright browser bundle covers all four, Intel macOS included
        # (its browsers come from the 26.05 branch, which still has them).
        e2ePlatforms = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
          "x86_64-darwin"
        ];

        # Playwright end-to-end tests of the final web bundle: the tests
        # serve t2048-web with python's http.server and drive it with the
        # Playwright runner and browsers from nixpkgs — no npm install, no
        # network at test time.
        #
        # projectName selects the Playwright project to run; null runs
        # every project. The browsers all come from the one browser
        # bundle, so nothing new is built for the full suite.
        t2048-e2e =
          projectName:
          let
            full = projectName == null;
          in
          pkgs.stdenv.mkDerivation {
            pname = if full then "t2048-e2e-full" else "t2048-e2e-${projectName}";
            version = "dev";
            src = ./tests;

            nativeBuildInputs = [
              pkgs.playwright-test
              pkgs.python3
            ];

            # The application under test: the final t2048-web bundle
            # (index.html, index.js, t2048.wasm), served by the test suite.
            T2048_APP_DIR = "${t2048-web}";

            buildPhase = ''
              runHook preBuild
              export CI=1                       # always start our own server
              export HOME="$TMPDIR"             # browsers want a writable home
              export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
              # WebKit's headless WPE backend needs an EGL display, but its
              # libEGL is libglvnd, which finds no vendor ICD in the pure
              # sandbox (there is no host /usr to bridge to, nixGL-style,
              # and no X/Wayland or GPU either). Hand it nixpkgs mesa's ICD
              # and the surfaceless platform: software GL from the store,
              # the same everywhere — reproducible, GPU-less.
              export __EGL_VENDOR_LIBRARY_DIRS="${pkgs.mesa}/share/glvnd/egl_vendor.d"
              export EGL_PLATFORM=surfaceless
              # stream the run and write it to $out/report, so a successful
              # build still shows its results:
              #   nix build .#t2048-e2e-full && cat result/report
              set -o pipefail
              {
                echo "Running the T2048 e2e tests on ${system}: ${
                  if full then "all browsers — the full suite" else "${projectName} — the quick suite"
                }"
                playwright test --reporter=line ${lib.optionalString (!full) "--project=${projectName}"} 2>&1
              } | tee report
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp report $out/report
              runHook postInstall
            '';

            meta = {
              description = "Playwright e2e tests of the T2048 web build (${if full then "all browsers" else projectName})";
              license = lib.licenses.mit;
              platforms = e2ePlatforms;
            };
          };
      in
      {
        packages = {
          default = t2048-web;
          t2048-web = t2048-web;
          T2048 = t2048;
          rocq-with-t2048 = rocq-with-t2048;
          # the full suite, every browser of the config's projects: what
          # CI runs (nix build .#t2048-e2e-full)
          t2048-e2e-full = t2048-e2e null;
        };

        checks = {
          # the quick suite, chromium only: keeps `nix flake check` fast;
          # CI runs the full suite on every platform
          t2048-e2e = t2048-e2e "chromium";
        };

        devShells.default = pkgs.mkShell {
          name = "T2048";
          packages = [
            rocqPackages.rocq-core
            coqPackages.coq
            coqPackages.CertiRocq
            coqPackages.stdlib
            coqPackages.coq-lsp
            t2048
            pkgs.gnumake
            pkgs.nodejs_22
            pkgs.python3
            # to run the e2e suite by hand: cd tests && playwright test
            pkgs.playwright-test
          ];

          COQBIN = "${coqPackages.coq}/bin/";

          # WebKit's headless EGL in manual runs (`cd tests && playwright
          # test`): same setup as the check targets above — mesa's ICD and
          # the surfaceless platform, so it works on headless hosts too.
          __EGL_VENDOR_LIBRARY_DIRS = "${pkgs.mesa}/share/glvnd/egl_vendor.d";
          EGL_PLATFORM = "surfaceless";

          shellHook = ''
            echo "T2048 development environment"
            echo "  rocq:  $(rocq --version | head -1)"
            echo "  coq:   $(coqc --version | head -1)"
            echo "  node:  $(node --version)"
            echo ""
            echo "Build the web bundle:  nix build  (or: make)"
            echo "Serve it:              cd result && python3 -m http.server"
            echo "End-to-end tests:      nix flake check  (or: cd tests && playwright test)"
          '';
        };
      }
    );
}
