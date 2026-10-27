{
  description = "Purdue Hackers Minecraft distribution";

  # Freesm's binary cache. Players are asked whether to trust it; without it, Freesm builds from source (several minutes).
  nixConfig = {
    extra-substituters = [ "https://freesmlauncher.cachix.org" ];
    extra-trusted-public-keys = [ "freesmlauncher.cachix.org-1:Jcp5Q9wiLL+EDv8Mh7c6L9xGk+lXr7/otpKxMOuBuDs=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Not in nixpkgs. Don't make it follow our nixpkgs: its own lock is what its cachix has built.
    freesm.url = "github:FreesmTeam/FreesmLauncher/2.3.1";
  };

  outputs = { self, nixpkgs, freesm }:
    let
      allSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = systems: f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      # `nix run github:srgaabriel/ph-mc`: Freesm Launcher with a pinned Java 21, seeded with the instance on first run
      packages = forAll linuxSystems (pkgs:
        let
          jdk = pkgs.jdk21;
          launcher = freesm.packages.${pkgs.system}.freesmlauncher.override { jdks = [ jdk ]; };
          bootstrap = pkgs.fetchurl {
            url = "https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar";
            hash = "sha256-qPuyTcYEJ46X9GiOgtPZGjGLmO/AjV2/y8vKtkQ9EWw=";
          };
          template = pkgs.runCommand "ph-mc-template" { } ''
            cp -R ${./launcher/template} $out
            chmod -R u+w $out
            rm -f "$out/instances/Purdue Hackers/minecraft/.gitkeep"
            cp ${bootstrap} "$out/instances/Purdue Hackers/minecraft/packwiz-installer-bootstrap.jar"
          '';
        in {
          default = pkgs.writeShellApplication {
            name = "ph-mc";
            runtimeInputs = [ pkgs.coreutils pkgs.gawk ];
            text = ''
              export PH_LAUNCHER=${launcher}/bin/freesmlauncher
              export PH_TEMPLATE=${template}
              export PH_DATA="''${XDG_DATA_HOME:-$HOME/.local/share}/ph-mc"
              export PH_JAVA=${jdk}/bin/java
              exec bash ${./launcher/run.sh} "$@"
            '';
          };
        });

      devShells = forAll allSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ packwiz just python3 rsync curl zip unzip ];
        };
      });
    };
}
