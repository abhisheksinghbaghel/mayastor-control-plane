{ git, lib, stdenv, clang, openapi-generator, pkgs, which, sources }:
let
  versionDrv = import ../../lib/version.nix { inherit lib stdenv git; };
  version = builtins.readFile "${versionDrv}";
  channel = import ../../lib/rust.nix { inherit sources; };
  project-builder =
    pkgs.callPackage ../control-plane/cargo-project.nix { inherit version; };
  whitelistSource = src: allowedPrefixes:
    builtins.filterSource
      (path: type:
        lib.any
          (allowedPrefix: lib.hasPrefix (toString (src + "/${allowedPrefix}")) path)
          allowedPrefixes)
      src;
  src = whitelistSource ../../../. project-builder.src_list;

  naersk_package = channel: pkgs.callPackage sources.naersk {
    rustc = channel.stable;
    cargo = channel.stable;
  };
  naersk = naersk_package channel.static;
  naersk_cross = naersk_package channel.windows_cross;
  arch = with lib; head (splitString "-" stdenv.hostPlatform.system);

  components = { release ? false }: {
    windows-gnu = {
      kubectl-plugin = naersk_cross.buildPackage {
        inherit release src version;
        name = "kubectl-plugin";

        preBuild = ''
          # don't run during the dependency build phase
          if [ ! -f build.rs ]; then
            patchShebangs ./scripts/rust/generate-openapi-bindings.sh
            ./scripts/rust/generate-openapi-bindings.sh
          fi
          sed -i '/ctrlp-tests.*=/d' ./kubectl-plugin/Cargo.toml
          export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS="-C link-args=''$(echo $NIX_LDFLAGS | tr ' ' '\n' | grep -- '^-L' | tr '\n' ' ')"
          export NIX_LDFLAGS=
        '';
        cargoBuildOptions = attrs: attrs ++ [ "-p" "kubectl-plugin" "--no-default-features" "--features" "tls" ];
        buildInputs = with pkgs.pkgsCross.mingwW64.windows; [ mingw_w64_pthreads pthreads ];
        nativeBuildInputs = [ pkgs.pkgsCross.mingwW64.clangStdenv.cc openapi-generator which git ];
        doCheck = false;
        usePureFromTOML = true;

        CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
        CARGO_BUILD_TARGET = "x86_64-pc-windows-gnu";
        CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = with pkgs.pkgsCross.mingwW64.clangStdenv;
          "${cc}/bin/${cc.targetPrefix}cc";
      };
      recurseForDerivations = true;
    };
    linux-musl = {
      kubectl-plugin = naersk.buildPackage {
        inherit release src version;
        name = "kubectl-plugin";

        preBuild = ''
          # don't run during the dependency build phase
          if [ ! -f build.rs ]; then
            patchShebangs ./scripts/rust/generate-openapi-bindings.sh
            ./scripts/rust/generate-openapi-bindings.sh
          fi
          sed -i '/ctrlp-tests.*=/d' ./kubectl-plugin/Cargo.toml
        '';
        cargoBuildOptions = attrs: attrs ++ [ "-p" "kubectl-plugin" ];
        nativeBuildInputs = [ clang openapi-generator which git ];
        doCheck = false;
        usePureFromTOML = true;

        CARGO_BUILD_TARGET = "${arch}-unknown-linux-musl";
        CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
      };
      recurseForDerivations = true;
    };
    apple-darwin = {
      kubectl-plugin = naersk.buildPackage {
        inherit release src version;
        name = "kubectl-plugin";

        preBuild = ''
          # don't run during the dependency build phase
          if [ ! -f build.rs ]; then
            patchShebangs ./scripts/rust/generate-openapi-bindings.sh
            ./scripts/rust/generate-openapi-bindings.sh
          fi
          sed -i '/ctrlp-tests.*=/d' ./kubectl-plugin/Cargo.toml
        '';
        cargoBuildOptions = attrs: attrs ++ [ "-p" "kubectl-plugin" ];
        nativeBuildInputs = [ clang openapi-generator which git ];
        doCheck = false;
        usePureFromTOML = true;

        CARGO_BUILD_TARGET = "x86_64-apple-darwin";
        CARGO_BUILD_RUSTFLAGS = "-C target-feature=+crt-static";
      };
      recurseForDerivations = true;
    };
  };
in
{
  inherit version;

  release = components { release = true; };
  debug = components { release = false; };
}
