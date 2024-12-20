{
  description = "flake for pluralkit";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/x86_64-linux";
    process-compose.url = "github:Platonic-Systems/process-compose-flake";
    services.url = "github:juspay/services-flake";
    d2n.url = "github:nix-community/dream2nix/rust-cargo-vendor/git-replace-workspace-attributes";
    d2n.inputs.nixpkgs.follows = "nixpkgs";
    nci.url = "github:yusdacra/nix-cargo-integration";
    nci.inputs.nixpkgs.follows = "nixpkgs";
    nci.inputs.dream2nix.follows = "d2n";
  };

  outputs =
    inp:
    inp.parts.lib.mkFlake { inputs = inp; } {
      systems = import inp.systems;
      imports = [
        inp.process-compose.flakeModule
        inp.nci.flakeModule
      ];
      perSystem =
        {
          config,
          self',
          pkgs,
          system,
          ...
        }:
        let
          dataDir = ".nix-dev-data";
          pluralkitConfCheck = ''
            [[ -f "pluralkit.conf" ]] || (echo "pluralkit config not found, please copy pluralkit.conf.example to pluralkit.conf and edit it" && exit 1)
          '';
          sourceDotenv = ''
            [[ -f ".env" ]] && echo "sourcing .env file..." && export "$(xargs < .env)"
          '';

          rustOutputs = config.nci.outputs;
          composeCfg = config.process-compose."dev";
        in
        {
          _module.args.pkgs = import inp.nixpkgs {
            inherit system;
            config.permittedInsecurePackages = [ "dotnet-sdk-6.0.428" ];
          };

          nci.toolchainConfig = {
            channel = "nightly";
          };
          nci.projects."pluralkit-services" = {
            path = ./.;
          };
          nci.crates."gateway" = {
            depsDrvConfig.mkDerivation = {
              nativeBuildInputs = [ pkgs.protobuf ];
            };
            drvConfig.mkDerivation = {
              nativeBuildInputs = [ pkgs.protobuf ];
            };
          };

          formatter = pkgs.nixfmt-rfc-style;
          devShells = {
            default = rustOutputs."pluralkit-services".devShell;
          };

          process-compose."dev" = {
            imports = [ inp.services.processComposeModules.default ];

            settings.environment = {
              DOTNET_CLI_TELEMETRY_OPTOUT = "1";
              NODE_OPTIONS = "--openssl-legacy-provider";
            };

            services.redis."redis" = {
              enable = true;
              dataDir = "${dataDir}/redis";
            };
            services.postgres."postgres" = {
              enable = true;
              dataDir = "${dataDir}/postgres";
              initialScript.before = ''
                CREATE DATABASE pluralkit;
                CREATE USER postgres WITH password 'postgres';
                GRANT ALL PRIVILEGES ON DATABASE pluralkit TO postgres;
                ALTER DATABASE pluralkit OWNER TO postgres;
              '';
            };

            settings.processes =
              let
                procCfg = composeCfg.settings.processes;
              in
              {
                pluralkit-bot = {
                  command = pkgs.writeShellApplication {
                    name = "pluralkit-bot";
                    runtimeInputs = with pkgs; [
                      coreutils
                      podman
                    ];
                    text = ''
                      ${sourceDotenv}
                      set -x
                      ${pluralkitConfCheck}
                      podman build --tag='pluralkit' .
                      mkdir -p "${dataDir}/pluralkit/log"
                      exec podman run -t --volume ./pluralkit.conf:/app/pluralkit.conf:ro --volume ${dataDir}/pluralkit/log:/var/log/pluralkit --net=host 'pluralkit'
                    '';
                  };
                  depends_on.postgres.condition = "process_healthy";
                  depends_on.redis.condition = "process_healthy";
                  depends_on.pluralkit-gateway.condition = "process_healthy";
                  shutdown.signal = 9; # KILL
                };
                pluralkit-gateway =
                  let
                    shell = rustOutputs."gateway".devShell;
                  in
                  {
                    command = pkgs.writeShellApplication {
                      name = "pluralkit-gateway";
                      runtimeInputs =
                        (with pkgs; [
                          curl
                          gnugrep
                          coreutils
                          protobuf
                          shell.stdenv.cc
                        ])
                        ++ shell.nativeBuildInputs;
                      text = ''
                        ${sourceDotenv}
                        set -x
                        ${pluralkitConfCheck}
                        exec cargo run --package gateway
                      '';
                    };
                    depends_on.postgres.condition = "process_healthy";
                    depends_on.redis.condition = "process_healthy";
                    # configure health checks
                    liveness_probe.exec.command = ''curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/stats | grep "302"'';
                    readiness_probe.exec.command = procCfg.pluralkit-gateway.liveness_probe.exec.command;
                  };
              };
          };
        };
    };
}
