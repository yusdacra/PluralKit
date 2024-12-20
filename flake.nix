{
  description = "flake for pluralkit";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/x86_64-linux";
    process-compose.url = "github:Platonic-Systems/process-compose-flake";
    services.url = "github:juspay/services-flake";
  };

  outputs =
    inp:
    inp.parts.lib.mkFlake { inputs = inp; } {
      systems = import inp.systems;
      imports = [
        inp.process-compose.flakeModule
      ];
      perSystem =
        {
          self',
          pkgs,
          lib,
          system,
          ...
        }:
        let
          dataDir = ".nix-dev-data";
          pluralkitConfCheck = ''
            [[ -f "pluralkit.conf" ]] || (echo "pluralkit config not found, please copy pluralkit.conf.example to pluralkit.conf and edit it" && exit 1)
          '';
        in
        {
          _module.args.pkgs = import inp.nixpkgs {
            inherit system;
            config.permittedInsecurePackages = ["dotnet-sdk-6.0.428"];
          };
          formatter = pkgs.nixfmt-rfc-style;
          devShells = {
            pluralkit = pkgs.mkShellNoCC {
              packages = with pkgs; [
                cargo rust-analyzer rustfmt
                gcc
                protobuf
                dotnet-sdk_6
                omnisharp-roslyn
                go
                nodejs yarn
              ];

              NODE_OPTIONS = "--openssl-legacy-provider";
            };
            default = self'.devShells.pluralkit;
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

            settings.processes = {
              pluralkit-bot = {
                command = pkgs.writeShellApplication {
                  name = "pluralkit-bot";
                  runtimeInputs = with pkgs; [coreutils podman];
                  text = ''
                    set -x
                    ${pluralkitConfCheck}
                    echo "building pluralkit docker image"
                    podman build --tag='pluralkit' .
                    mkdir -p "${dataDir}/pluralkit/log"
                    exec podman run -t --volume ./pluralkit.conf:/app/pluralkit.conf:ro --volume ${dataDir}/pluralkit/log:/var/log/pluralkit --net=host 'pluralkit'
                  '';
                };
                depends_on.postgres.condition = "process_healthy";
                depends_on.redis.condition = "process_healthy";
                shutdown.signal = 9; # KILL
              };
              # pluralkit-gateway = {
              #   command = pkgs.writeShellApplication {
              #     name = "pluralkit-gateway";
              #     runtimeInputs = with pkgs; [coreutils];
              #     text = ''
              #       set -x
              #       ${pluralkitConfCheck}
              #       exec 
              #     '';
              #   };
              # };
            };
          };
        };
    };
}
