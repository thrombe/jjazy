{
  description = "yaaaaaaaaaaaaaaaaaaaaa";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    zls = {
      url = "github:zigtools/zls/0.14.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.zig-overlay.follows = "zig-overlay";
    };

    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = inputs:
    inputs.flake-utils.lib.eachDefaultSystem (system: let
      flakePackage = flake: package: flake.packages."${system}"."${package}";
      flakeDefaultPackage = flake: flakePackage flake "default";

      # - [zig-overlay/sources.json](https://github.com/mitchellh/zig-overlay/blob/main/sources.json)
      zig-env = inputs.zig2nix.zig-env.${system};
      zigv = pkgs.callPackage "${inputs.zig2nix}/zig.nix" rec {
        zigSystem = (zig-env {}).lib.zigDoubleFromString system;
        zigHook = (zig-env {}).zig-hook;
        # - [get info from](https://machengine.org/zig/index.json)
        version = "0.14.0";
        release = {
          "version" = version;
          "x86_64-linux" = {
            "shasum" = "sha256-Rz7CaAYTPPTRkYyvGkEPhAOhPZeXJqkEW0IbaFAxqYI=";
            "size" = "";
            "zigTarball" = "https://pkg.machengine.org/zig/zig-linux-x86_64-${version}.tar.xz";
            "tarball" = "https://ziglang.org/builds/zig-linux-x86_64-${version}.tar.xz";
          };
        };
      };
      overlays = [
        (self: super: rec {
          zig = zigv.bin;
          zls = (flakePackage inputs.zls "zls").overrideAttrs (old: {
            nativeBuildInputs = [ zig ];
            buildInputs = [ zig ];
          });
        })
      ];

      pkgs = import inputs.nixpkgs {
        config.allowUnfree = true;
        inherit system;
        inherit overlays;
      };

      fhs = pkgs.buildFHSEnv {
        name = "fhs-shell";
        targetPkgs = p: (env-packages p) ++ (custom-commands p);
        runScript = "${pkgs.zsh}/bin/zsh";
        profile = ''
          export FHS=1
          source ./.venv/bin/activate
          # source .env
        '';
      };
      custom-commands = pkgs: [
        (pkgs.writeShellScriptBin "todo" ''
          #!/usr/bin/env bash
          cd $PROJECT_ROOT
        '')
      ];

      env-packages = pkgs:
        (with pkgs; [
          pkg-config

          zig

          zls
          gdb
        ])
        ++ []
        ++ (custom-commands pkgs);

      stdenv = pkgs.clangStdenv;
    in {
      packages = {};
      overlays = {};

      devShells.default =
        pkgs.mkShell.override {
          inherit stdenv;
        } {
          nativeBuildInputs = (env-packages pkgs) ++ [fhs];
          inputsFrom = [];
          shellHook = ''
            export PROJECT_ROOT="$(pwd)"
            export CLANGD_FLAGS="--compile-commands-dir=$PROJECT_ROOT --query-driver=$(which $CXX)"
          '';
        };
    });
}
