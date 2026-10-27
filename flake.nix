{
  description = "Purdue Hackers Minecraft distribution";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      allSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = systems: f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      # `nix run github:srgaabriel/ph-mc`: nixpkgs Prism with a pinned Java 21, seeded with the instance on first run
      packages = forAll linuxSystems (pkgs:
        let
          jdk = pkgs.jdk21;
          prism = pkgs.prismlauncher.override { jdks = [ jdk ]; };
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
              export PH_PRISM=${prism}/bin/prismlauncher
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
